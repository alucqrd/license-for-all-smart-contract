
pragma solidity ^0.4.18;
import 'zeppelin-solidity/contracts/lifecycle/Pausable.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';

contract LicenseForAllBase {
    event ContractUpgrade(address newContract);
    event Transfer(address from, address to, uint256 tokenId);
    event Approval(address owner, address approved, uint256 tokenId, uint256 price);

    struct License {
        uint256 licenseTypeId;
        uint64 creationTime;
        // Cut creator takes on each resale, measured in basis points (1/100 of a percent).
        // Values 0-10,000 map to 0%-100%
        uint256 cutOnResale;
    }

    struct SaleApproval {
        address to;
        uint256 price;
        uint64 creationTime;
    }

    // Array containing every licenses
    License[] licenses;

    // Array containing every license type id with creator address associated
    address[] licenseTypeIdToCreator;

    // Mapping of each license and user association
    mapping (uint256 => address) public licenseIndexToOwner;

    // Mapping from license ID to approved address
    mapping (uint256 => SaleApproval) public licenseIndexToApproved;

    // @dev A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.
    mapping (address => uint256) ownershipTokenCount;

    /// @dev Assigns ownership of a specific License to an address.
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        // Since the number of licenses is capped to 2^32 we can't overflow this
        ownershipTokenCount[_to]++;
        // transfer ownership
        licenseIndexToOwner[_tokenId] = _to;

        // When creating new licenses _from is 0x0, but we can't account that address.
        if (_from != address(0)) {
            ownershipTokenCount[_from]--;
        }

        // Emit the transfer event.
        Transfer(_from, _to, _tokenId);
    }

    /// @dev An internal method that creates a new license type id and associates it with its creator.
    /// @param _creator The address of the creator.
    function _createLicenseTypeId(address _creator) internal returns (uint) {
        // Increment the licenseTypeIdToCreator array and associate the creator address to new license type id
        uint256 newLicenseTypeId = licenseTypeIdToCreator.push(_creator) - 1;
        // Let's just be 100% sure we never let this happen.
        require(newLicenseTypeId == uint256(uint32(newLicenseTypeId)));
        // Return the license type id
        return newLicenseTypeId;
    }

    /// @dev An internal method that creates a new license and stores it. Will generate a Transfer event.
    /// @param _licenseTypeId The ID of the license type.
    /// @param _cutOnResale The cut wanted to go back to license creator on resale.
    /// @param _owner The inital owner of this license, must be non-zero.
    function _createLicense(uint256 _licenseTypeId, uint256 _cutOnResale, address _owner) internal returns (uint256) {
        // Check that cut on resale is under or equal 100%
        require(_cutOnResale <= 10000);
        // Check that license type id exists
        require(_licenseTypeId < licenseTypeIdToCreator.length);
        // Check that the future owner of the new license is the creator
        require(licenseTypeIdToCreator[_licenseTypeId] == _owner);

        License memory _license = License({
            licenseTypeId: _licenseTypeId,
            creationTime: uint64(now),
            cutOnResale: _cutOnResale
        });

        uint256 newLicenseId = licenses.push(_license) - 1;

        // Let's just be 100% sure we never let this happen.
        require(newLicenseId == uint256(uint32(newLicenseId)));

        // This will assign ownership, and also emit the Transfer event.
        _transfer(0, _owner, newLicenseId);

        return newLicenseId;
    }
}

contract LicenseForAllOwnership is LicenseForAllBase, Pausable {
  using SafeMath for uint256;

  string public constant name = "LicenseForAll";
  string public constant symbol = "LFA";

    // Internal utility functions: These functions all assume that their input arguments
    // are valid. We leave it to public methods to sanitize their inputs and follow
    // the required logic.

    /// @dev Checks if a given address is the current owner of a particular License.
    /// @param _claimant the address we are validating against.
    /// @param _tokenId license id, only valid when > 0
    function _owns(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return licenseIndexToOwner[_tokenId] == _claimant;
    }

    /// @dev Checks if a given address currently has transferApproval for a particular License.
    /// @param _claimant the address we are confirming license is approved for. If it is set to 0, it means that anybody can call transferFrom with asked price.
    /// @param _tokenId license id, only valid when > 0
    function _approvedFor(address _claimant, uint256 _tokenId, uint256 _price) internal view returns (bool) {
        return ((licenseIndexToApproved[_tokenId].to == _claimant || licenseIndexToApproved[_tokenId].to == 0)  && licenseIndexToApproved[_tokenId].price <= _price);
    }

    /// @dev Marks an address as being approved for transferFrom(), overwriting any previous
    ///  approval. Setting _approved to address(0) clears all transfer approval.
    function _approve(uint256 _tokenId, address _to, uint256 _price) internal {
        address owner = ownerOf(_tokenId);
        require(_to != owner);
        delete licenseIndexToApproved[_tokenId];

        SaleApproval memory approval = SaleApproval({
            to: _to,
            price: _price,
            creationTime: uint64(now)
        });

        licenseIndexToApproved[_tokenId] = approval;
        Approval(owner, _to, _tokenId, _price);
    }

    /// @notice Returns the number of Licenses owned by a specific address.
    /// @param _owner The owner address to check.
    function balanceOf(address _owner) public view returns (uint256 count) {
        return ownershipTokenCount[_owner];
    }
    
    /// @notice Grant another address the right to transfer a specific License via
    ///  transferFrom().
    /// @param _to The address to be granted transfer approval. Pass address(0) to
    ///  clear all approvals.
    /// @param _tokenId The ID of the License that can be transferred if this call succeeds.
    /// @param _price The price agreed, so when transferFrom is called, we check that the transaction has the right amount of funds.
    function approve(address _to, uint256 _tokenId, uint256 _price) external whenNotPaused {
        // Only an owner can grant transfer approval.
        require(_owns(msg.sender, _tokenId));

        // Register the approval (replacing any previous approval).
        _approve(_tokenId, _to, _price);

        // Emit approval event.
        Approval(msg.sender, _to, _tokenId, _price);
    }

    /// @notice Transfer a License owned by another address, for which the calling address
    ///  has previously been granted transfer approval by the owner.
    /// @param _from The address that owns the License to be transfered.
    /// @param _to The address that should take ownership of the License. Can be any address,
    ///  including the caller.
    /// @param _tokenId The ID of the License to be transferred.
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable whenNotPaused {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));

        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any licenses. (Just at the moment for testing purpose)
        //require(_to != address(this));

        // Check for approval and valid ownership
        require(_approvedFor(msg.sender, _tokenId, msg.value));
        require(_owns(_from, _tokenId));

        // Compute and send cut to license creator
        uint256 cut = msg.value.mul(licenses[_tokenId].cutOnResale.div(10000));
        licenseIndexToOwner[_tokenId].transfer(cut);

        // Transfer payment to seller
        _from.transfer(msg.value - cut);

        // Reassign ownership (also clears pending approvals and emits Transfer event).
        _transfer(_from, _to, _tokenId);
    }

    /// @notice Returns the total number of Licenses currently in existence.
    function totalSupply() public view returns (uint) {
        return licenses.length;
    }

    /// @notice Returns the address currently assigned ownership of a given License.
    function ownerOf(uint256 _tokenId) public view returns (address owner) {
        owner = licenseIndexToOwner[_tokenId];
        require(owner != address(0));
        return owner;
    }
}

contract LicenseForAllCore is LicenseForAllOwnership {
    // Set in case the core contract is broken and an upgrade is required
    address public newContractAddress;

    function LicenseForAllCore() public {
        // Starts paused.
        paused = true;

        // the creator of the contract is the owner
        owner = msg.sender;

        // This func is be called in contract constructor to generate some testing licenses data, must be removed before live deployment (ofc!!)
        _testingStuff();
    }

    /// @dev This func will be called in contract constructor to generate some testing licenses data, must be removed before live deployment (ofc!!)
    function _testingStuff() internal {
        uint256 firstLicenseType = _createLicenseTypeId(this);
        uint256 secondLicenseType = _createLicenseTypeId(this);

        _createLicense(firstLicenseType, 0, this);
        _createLicense(firstLicenseType, 0, this);
        _createLicense(firstLicenseType, 0, this);
        _createLicense(secondLicenseType, 1, this);
        _createLicense(secondLicenseType, 5000, this);
    }

    /// @dev Used to mark the smart contract as upgraded, in case there is a serious
    ///  breaking bug. This method does nothing but keep track of the new contract and
    ///  emit a message indicating that the new address is set. It's up to clients of this
    ///  contract to update to the new contract address in that case. (This contract will
    ///  be paused indefinitely if such an upgrade takes place.)
    /// @param _v2Address new address
    function setNewAddress(address _v2Address) external onlyOwner whenPaused {
        // See README.md for updgrade plan
        newContractAddress = _v2Address;
        ContractUpgrade(_v2Address);
    }

    /// @dev An external method that creates a new license type id and associates it with its creator.
    /// @param _creator The address of the creator.
    function createLicenseTypeId(address _creator) external onlyOwner {
        _createLicenseTypeId(_creator);
    }

    /// @dev An external method that creates a new license and stores it.
    /// @param _licenseTypeId The ID of the license type.
    /// @param _cutOnResale The cut wanted to go back to license creator on resale.
    /// @param _owner The inital owner of this license, must be non-zero.
    function createLicense(uint32 _licenseTypeId, uint256 _cutOnResale, address _owner) external {
        _createLicense(_licenseTypeId, _cutOnResale, _owner);
    }

    /// @notice Returns all the relevant information about a specific license.
    /// @param _id The ID of the license of interest.
    function getLicense(uint256 _id)
        external
        view
        returns (
        uint256 licenseTypeId,
        uint64 creationTime,
        uint256 cutOnResale
    ) {
        License storage lic = licenses[_id];

        licenseTypeId = uint256(lic.licenseTypeId);
        creationTime = uint64(lic.creationTime);
        cutOnResale = uint256(lic.cutOnResale);
    }
}