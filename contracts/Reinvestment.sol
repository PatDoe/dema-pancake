pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./Interface/IReinvestment.sol";
import "./Interface/IMasterChef.sol";
import "./utils/SafeToken.sol";


contract Reinvestment is Ownable, IReinvestment {
    /// @notice Libraries
    using SafeToken for address;
    using SafeMath for uint256;

    /// @notice Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    address cake;
    IMasterChef public masterChef;
    uint256 public masterChefPid;        // cake pid in master chef , should be 0 in BSC

    /// @notice Mutable state variables

    struct GlobalInfo {
        uint256 totalShares;        // Total staked lp amount.
        uint256 totalCake;           // Total cake amount that already staked to board room.
        uint256 accCakePerShare;     // Accumulate cake rewards amount per lp token.
        uint256 lastUpdateTime;
    }

    struct UserInfo {
        uint256 totalShares;            // Total Lp amount.
        uint256 earnedCakeStored;        // Earned cake amount stored at the last time user info was updated.
        uint256 accCakePerShareStored;   // The accCakePerShare at the last time user info was updated.
        uint256 lastUpdateTime;
    }

    mapping(address => UserInfo) public userInfo;
    GlobalInfo public globalInfo;
    uint256 public override reservedRatio;       // Reserved share ratio. will divide by 10000, 0 means not reserved.

    constructor(
        IMasterChef _masterChef,
        uint256 _masterChefPid,          // Should be 4 in BSC
        address _cake,
        uint256 _reserveRatio           // will divide by 10000, 0 means not reserved.
    ) public {
        masterChef = _masterChef;
        masterChefPid = _masterChefPid;
        cake = _cake;
        reservedRatio = _reserveRatio;

        cake.safeApprove(address(masterChef), uint256(-1));
    }

    /* ==================================== Read ==================================== */

    function totalRewards() public  view returns (uint256) {
        (uint256 deposited, /* rewardDebt */) = masterChef.userInfo(masterChefPid, address(this));
        return cake.myBalance().add(deposited).add(masterChef.pendingCake(masterChefPid, address(this)));
    }

    // TODO need to mul(1e18) and div(1e18) in other place used this function.
    function rewardsPerShare() public view  returns (uint256) {
        if (globalInfo.totalShares != 0) {
            // globalInfo.totalCake is the cake amount at the last time update.
            return (totalRewards().sub(globalInfo.totalCake)).mul(1e18).div(
                globalInfo.totalShares).add(globalInfo.accCakePerShare);
        } else {
            return globalInfo.accCakePerShare;
        }
    }

    /// @notice Goblin is the user.
    function userEarnedAmount(address account) public view override returns (uint256) {
        UserInfo storage user = userInfo[account];
        return user.totalShares.mul(rewardsPerShare().sub(user.accCakePerShareStored)).div(1e18).add(user.earnedCakeStored);
    }

    /* ==================================== Write ==================================== */

    // Deposit cake.
    function deposit(uint256 amount) external override {
        if (amount > 0) {
            _updatePool(msg.sender);
            cake.safeTransferFrom(msg.sender, address(this), amount);

            UserInfo storage user = userInfo[msg.sender];
            uint256 shares = _amountToShare(amount);

            // Update global info first
            globalInfo.totalCake = globalInfo.totalCake.add(amount);
            globalInfo.totalShares = globalInfo.totalShares.add(shares);

            // If there are some reserved shares
            if (reservedRatio != 0) {
                UserInfo storage owner = userInfo[owner()];
                uint256 ownerShares = shares.mul(reservedRatio).div(10000);
                uint256 ownerAmount = amount.mul(reservedRatio).div(10000);
                owner.totalShares = owner.totalShares.add(ownerShares);
                owner.earnedCakeStored = owner.earnedCakeStored.add(ownerAmount);

                // Calculate the left shares
                shares = shares.sub(ownerShares);
                amount = amount.sub(ownerAmount);
            }

            user.totalShares = user.totalShares.add(shares);
            user.earnedCakeStored = user.earnedCakeStored.add(amount);
        }
    }

    // Withdraw cake to sender.
    function withdraw(uint256 amount) external override {
        if (amount > 0) {
            require(userInfo[msg.sender].earnedCakeStored >= amount, "User don't have enough amount");

            _updatePool(msg.sender);
            UserInfo storage user = userInfo[msg.sender];

            bool isWithdraw = false;
            if (cake.myBalance() < amount) {
                // If balance is not enough Withdraw from board room first.
                (uint256 depositedPancake, /* rewardDebt */) = masterChef.userInfo(masterChefPid, address(this));
                masterChef.withdraw(masterChefPid, depositedPancake);
                isWithdraw = true;
            }
            cake.safeTransfer(msg.sender, amount);

            // Update left share and amount.
            uint256 share = _amountToShare(amount);
            globalInfo.totalShares = globalInfo.totalShares.sub(share);
            globalInfo.totalCake = globalInfo.totalCake.sub(amount);
            user.totalShares = user.totalShares.sub(share);
            user.earnedCakeStored = user.earnedCakeStored.sub(amount);

            // If withdraw cake from board room, we need to redeposit.
            if (isWithdraw) {
                masterChef.deposit(masterChefPid, cake.myBalance());
            }
        }
    }

    function reinvest() external {
        masterChef.withdraw(masterChefPid, 0);
        masterChef.deposit(masterChefPid, cake.myBalance());
    }

    /* ==================================== Internal ==================================== */

    /// @dev update pool info and user info.
    function _updatePool(address account) internal {
        if (globalInfo.lastUpdateTime != block.timestamp) {
            /// @notice MUST update accCakePerShare first as it will use the old totalCake
            globalInfo.accCakePerShare = rewardsPerShare();
            globalInfo.totalCake = totalRewards();
            globalInfo.lastUpdateTime = block.timestamp;
        }

        UserInfo storage user = userInfo[account];
        if (account != address(0) && user.lastUpdateTime != block.timestamp) {
            user.earnedCakeStored = userEarnedAmount(account);
            user.accCakePerShareStored = globalInfo.accCakePerShare;
            user.lastUpdateTime = block.timestamp;
        }
    }

    function _amountToShare(uint256 amount) internal view returns (uint256) {
        return globalInfo.totalCake == 0 ?
            amount : amount.mul(globalInfo.totalShares).div(globalInfo.totalCake);
    }

    /* ==================================== Only Owner ==================================== */

    // Used when boardroom is closed.
    function stopReinvest() external onlyOwner {
        (uint256 deposited, /* rewardDebt */) = masterChef.userInfo(masterChefPid, address(this));
        if (deposited > 0) {
            masterChef.withdraw(masterChefPid, deposited);
        }
    }
}