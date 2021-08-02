const PancakeFacory = artifacts.require("PancakeFacotry");
const PancakeStrategyAddTwoSidesOptimal = artifacts.require("PancakeStrategyAddTwoSidesOptimal.sol");
const PancakeStrategyWithdrawMinimizeTrading = artifacts.require("PancakeStrategyWithdrawMinimizeTrading");
const PancakeGoblin = artifacts.require("PancakeGoblin");
const Bank = artifacts.require("Bank");
const Farm = artifacts.require("Farm");
const UserProfile = artifacts.require("UserProfile");
const SyrupBar = artifacts.require('SyrupBar');
const Reinvestment = artifacts.require("Reinvestment");
const MasterChef = artifacts.require("MasterChef");
const PancakeRouter = artifacts.require("PancakeRouter");
const CakeToken = artifacts.require("CakeToken");
const WBNB = artifacts.require("WBNB");
const DEMA = artifacts.require("DEMA");
const WETH = artifacts.require("WETH");


const BigNumber = require("bignumber.js");

module.exports = async function (deployer, network, accounts) {
    if (network == "development") {
        await deployer.deploy(PancakeFacory, accounts[0]);
        await deployer.deploy(WETH);
        await deployer.deploy(CakeToken);
        await deployer.deploy(WBNB);
        await deployer.deploy(DEMA);
        await deployer.deploy(PancakeRouter, PancakeFacory.address, WETH.address);
        await deployer.deploy(SyrupBar, CakeToken.address);
        await deployer.deploy(MasterChef, CakeToken.address, SyrupBar.address, accounts[0], 50, 1);
    
        const token0 = WBNB.address;
        const token1 = DEMA.address;
        const liqStrategy = PancakeStrategyAddTwoSidesOptimal.address;
    
        const wbnbDemaLp = await PancakeFacory.createPair(token0, token1);
        const poolId = 0;
        const masterchefPoolId = 0;
    
    
        await deployer.deploy(UserProfile);
        await deployer.deploy(Farm, UserProfile.address, DEMA.address, 1000, 1000);
        await deployer.deploy(Bank, Farm.address);
        await deployer.deploy(Reinvestment, MasterChef.address, masterchefPoolId, CakeToken.address, 1000);
        await deployer.deploy(
            PancakeGoblin,
            Bank.address,
            Farm.address,
            poolId,
            Reinvestment.address,
            MasterChef.address,
            masterchefPoolId,
            PancakeRouter.address,
            CakeToken.address,
            WBNB.address,
            token0,
            token1,
            liqStrategy
        )
    } else {
        console.log("network is not the development!")
    }

};
