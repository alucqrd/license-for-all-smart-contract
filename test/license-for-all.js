import expectThrow from "./helpers/expectThrow";
var LicenseForAll = artifacts.require("LicenseForAllCore");

contract('LicenseForAll', async (accounts) => {
    it("Should be able to create a new license id with account[1] set as creator", async () => {
        let instance = await LicenseForAll.deployed();
        await instance.createLicenseTypeId(accounts[1]);
        assert.equal(await instance.licenseTypeIdToCreator.call(0), accounts[1], "First license id creator isn't accounts[1]");
    });

    it("Now accounts[1] should be able to generate some licenses with type id 0", async () => {
        let instance = await LicenseForAll.deployed();
        await instance.createLicense(0, 2000, accounts[1], {from: accounts[1]});
        await instance.createLicense(0, 2000, accounts[2], {from: accounts[1]});
        await instance.createLicense(0, 2000, accounts[1], {from: accounts[1]});
        await expectThrow(instance.createLicense(0, 2000, accounts[1], {from: accounts[2]}));
        await expectThrow(instance.createLicense(0, 15000, accounts[1], {from: accounts[1]}));
        assert.equal(await instance.licenseIndexToOwner.call(0), accounts[1], "accounts[1] is not owner of license id 0");
        assert.equal(await instance.licenseIndexToOwner.call(1), accounts[2], "accounts[2] is not owner of license id 1");
        assert.equal(await instance.licenseIndexToOwner.call(2), accounts[1], "accounts[1] is not owner of license id 2");
    });

    it("Should be able to pause/unpause contract", async () => {
        let instance = await LicenseForAll.deployed();
        await instance.unpause();
        assert.equal(await instance.paused.call(), false, "Contract is still paused");
        await instance.pause();
        assert.equal(await instance.paused.call(), true, "Contract is still unpaused");
        await instance.unpause();
        assert.equal(await instance.paused.call(), false, "Contract is still paused");
    });

    it("Should be able to transfert a license from accounts[1] to accounts[3]", async () => {
        let instance = await LicenseForAll.deployed();
        await instance.approve(accounts[3], 0, "1000000000000000000", {from: accounts[1]});
        await expectThrow(instance.approve(accounts[3], 0, "1000000000000000000", {from: accounts[3]}));
        let acc3balancebefore = web3.eth.getBalance(accounts[3]);
        let acc1balancebefore = web3.eth.getBalance(accounts[1]);
        let tx = await instance.transferFrom(accounts[1], accounts[3], 0, {from: accounts[3], value: "1000000000000000000"});
        let acc3balanceafter = web3.eth.getBalance(accounts[3]);
        let acc1balanceafter = web3.eth.getBalance(accounts[1]);
        let diffAcc3 = Math.round((acc3balancebefore - acc3balanceafter - (tx.receipt.gasUsed * 100000000000))/100000)*100000;
        let diffAcc1 = acc1balanceafter - acc1balancebefore;
        assert.equal(diffAcc3, 1000000000000000000, "Amount transfered didn't match price for accounts[3]");
        assert.equal(diffAcc1, 1000000000000000000, "Amount transfered didn't match price for accounts[1]");
    });

    it("Should be able to transfert a license from accounts[2] to accounts[3] (cut is sent to accounts[1] as he's the license creator)", async () => {
        let instance = await LicenseForAll.deployed();
        await instance.approve(accounts[3], 1, "1000000000000000000", {from: accounts[2]});
        let acc1balancebefore = web3.eth.getBalance(accounts[1]);
        let acc2balancebefore = web3.eth.getBalance(accounts[2]);
        let acc3balancebefore = web3.eth.getBalance(accounts[3]);
        let tx = await instance.transferFrom(accounts[2], accounts[3], 1, {from: accounts[3], value: "1000000000000000000"});
        let acc1balanceafter = web3.eth.getBalance(accounts[1]);
        let acc2balanceafter = web3.eth.getBalance(accounts[2]);
        let acc3balanceafter = web3.eth.getBalance(accounts[3]);
        let diffAcc3 = Math.round((acc3balancebefore - acc3balanceafter - (tx.receipt.gasUsed * 100000000000))/100000)*100000;
        let diffAcc2 = acc2balanceafter - acc2balancebefore;
        let diffAcc1 = acc1balanceafter - acc1balancebefore;
        assert.equal(diffAcc3, 1000000000000000000, "Amount transfered didn't match price for accounts[3]");
        assert.equal(diffAcc2, 800000000000000000, "Amount transfered didn't match price for accounts[2]");
        assert.equal(diffAcc1, 200000000000000000, "Amount transfered didn't match price for accounts[1]");
    });

    it("accounts[1] should be able to approve for accounts[2] and then approve for accounts[3]", async () => {
        let instance = await LicenseForAll.deployed();
        await instance.approve(accounts[2], 2, "2000000000000000000", {from: accounts[1]});
        await instance.approve(accounts[3], 2, "1000000000000000000", {from: accounts[1]});
        let acc3balancebefore = web3.eth.getBalance(accounts[3]);
        let acc1balancebefore = web3.eth.getBalance(accounts[1]);
        await expectThrow(instance.transferFrom(accounts[1], accounts[3], 2, {from: accounts[2], value: "2000000000000000000"}));
        let tx = await instance.transferFrom(accounts[1], accounts[3], 2, {from: accounts[3], value: "1000000000000000000"});
        let acc3balanceafter = web3.eth.getBalance(accounts[3]);
        let acc1balanceafter = web3.eth.getBalance(accounts[1]);
        let diffAcc3 = Math.round((acc3balancebefore - acc3balanceafter - (tx.receipt.gasUsed * 100000000000))/100000)*100000;
        let diffAcc1 = acc1balanceafter - acc1balancebefore;
        assert.equal(diffAcc3, 1000000000000000000, "Amount transfered didn't match price for accounts[3]");
        assert.equal(diffAcc1, 1000000000000000000, "Amount transfered didn't match price for accounts[1]");
    });

    it("Reject any amount of ether sent to the contract", async () => {
        let instance = await LicenseForAll.deployed();
        await expectThrow(instance.sendTransaction({from: accounts[2], value: "2000000000000000000"}));
    });
});