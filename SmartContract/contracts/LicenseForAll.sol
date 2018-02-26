pragma solidity ^0.4.18;
import 'zeppelin-solidity/contracts/lifecycle/Pausable.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';

contract LicenseForAllBase {

    /// @dev Transfer event as defined in current draft of ERC721. Emitted every time a license
    ///  ownership is assigned.
    event ContractUpgrade(address newContract);
    event Transfer(address from, address to, uint256 tokenId);
    event Approval(address owner, address approved, uint256 tokenId);

    struct License {
        uint32 licenseTypeId;
        uint64 creationTime;
        // Cut creator takes on each resale, measured in basis points (1/100 of a percent).
        // Values 0-10,000 map to 0%-100%
        uint256 cutOnResale;
    }

    // Array containing every licenses
    License[] licenses;

    // Mapping of each license and user association
    mapping (uint256 => address) public licenseIndexToOwner;

    // Mapping from license ID to approved address
    mapping (uint256 => address) public licenseIndexToApproved;

    // @dev A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.
    mapping (address => uint256) ownershipTokenCount;

    /// @dev Assigns ownership of a specific License to an address.
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        // Since the number of licenses is capped to 2^32 we can't overflow this
        ownershipTokenCount[_to]++;
        // transfer ownership
        licenseIndexToOwner[_tokenId] = _to;

        /*
        // When creating new licenses _from is 0x0, but we can't account that address.
        if (_from != address(0)) {
            ownershipTokenCount[_from]--;
        }*/

        // Emit the transfer event.
        Transfer(_from, _to, _tokenId);
    }

    /// @dev An internal method that creates a new license and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is known to be valid. Will generate a Transfer event.
    /// @param _licenseTypeId The ID of the license type.
    /// @param _owner The inital owner of this license, must be non-zero.
    /// @param _cutOnResale The cut wanted to go back to license creator on resale.
    function _createLicense(uint32 _licenseTypeId, address _owner, uint256 _cutOnResale) internal returns (uint) {
        require(_cutOnResale <= 10000);

        // TODO: CHECK FOR LICENSE TYPE ID : ID EXISTS CREATOR IS OWNER OF THE ID
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
    /// @param _claimant the address we are confirming license is approved for.
    /// @param _tokenId license id, only valid when > 0
    function _approvedFor(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return licenseIndexToApproved[_tokenId] == _claimant;
    }

    /// @dev Marks an address as being approved for transferFrom(), overwriting any previous
    ///  approval. Setting _approved to address(0) clears all transfer approval.
    function _approve(uint256 _tokenId, address _to) internal {
        address owner = ownerOf(_tokenId);
        require(_to != owner);
        if (licenseIndexToApproved[_tokenId] != 0 || _to != 0) {
            licenseIndexToApproved[_tokenId] = _to;
            Approval(owner, _to, _tokenId);
        }
    }

    /// @notice Returns the number of Licenses owned by a specific address.
    /// @param _owner The owner address to check.
    /// @dev Required for ERC-721 compliance
    function balanceOf(address _owner) public view returns (uint256 count) {
        return ownershipTokenCount[_owner];
    }

    /// @notice Transfers a License to another address. If transferring to a smart
    ///  contract be VERY CAREFUL to ensure that it is aware of ERC-721 (or
    ///  LicenseForAll specifically) or your License may be lost forever. Seriously.
    /// @param _to The address of the recipient, can be a user or contract.
    /// @param _tokenId The ID of the License to transfer.
    /// @dev Required for ERC-721 compliance.
    function transfer(address _to, uint256 _tokenId) external whenNotPaused {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));

        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any licenses.
        require(_to != address(this));

        // You can only send your own license.
        require(_owns(msg.sender, _tokenId));

        // Reassign ownership, clear pending approvals, emit Transfer event.
        _transfer(msg.sender, _to, _tokenId);
    }

    /// @notice Grant another address the right to transfer a specific License via
    ///  transferFrom(). This is the preferred flow for transfering NFTs to contracts.
    /// @param _to The address to be granted transfer approval. Pass address(0) to
    ///  clear all approvals.
    /// @param _tokenId The ID of the License that can be transferred if this call succeeds.
    /// @dev Required for ERC-721 compliance.
    function approve(address _to, uint256 _tokenId) external whenNotPaused {
        // Only an owner can grant transfer approval.
        require(_owns(msg.sender, _tokenId));

        // Register the approval (replacing any previous approval).
        _approve(_tokenId, _to);

        // Emit approval event.
        Approval(msg.sender, _to, _tokenId);
    }

    /// @notice Transfer a License owned by another address, for which the calling address
    ///  has previously been granted transfer approval by the owner.
    /// @param _from The address that owns the License to be transfered.
    /// @param _to The address that should take ownership of the License. Can be any address,
    ///  including the caller.
    /// @param _tokenId The ID of the License to be transferred.
    /// @dev Required for ERC-721 compliance.
    function transferFrom(address _from, address _to, uint256 _tokenId) external whenNotPaused {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));

        /*// Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any licenses (except very briefly
        // after a gen0 cat is created and before it goes on auction).
        require(_to != address(this));*/

        // Check for approval and valid ownership
        require(_approvedFor(msg.sender, _tokenId));
        require(_owns(_from, _tokenId));

        // Reassign ownership (also clears pending approvals and emits Transfer event).
        _transfer(_from, _to, _tokenId);
    }

    /// @notice Returns the total number of Licenses currently in existence.
    /// @dev Required for ERC-721 compliance.
    function totalSupply() public view returns (uint) {
        return licenses.length - 1;
    }

    /// @notice Returns the address currently assigned ownership of a given License.
    /// @dev Required for ERC-721 compliance.
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

    /// @notice Returns all the relevant information about a specific license.
    /// @param _id The ID of the license of interest.
    function getLicense(uint256 _id)
        external
        view
        returns (
        uint32 licenseTypeId,
        uint64 creationTime,
        uint32 cutOnResale
    ) {
        License storage lic = licenses[_id];

        licenseTypeId = uint32(lic.licenseTypeId);
        creationTime = uint64(lic.creationTime);
        cutOnResale = uint32(lic.cutOnResale);
    }
}