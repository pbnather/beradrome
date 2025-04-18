// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import 'contracts/Plugin.sol';

interface ICommunalFarm {
    struct LockedStake {
        bytes32 kek_id;
        uint256 start_timestamp;
        uint256 liquidity;
        uint256 ending_timestamp;
        uint256 lock_multiplier; 
    }
    function stakeLocked(uint256 amount, uint256 time) external;
    function withdrawLockedAll() external;
    function getReward() external;
    function lockedLiquidityOf(address account) external view returns (uint256);
    function lockedStakesOf(address account) external view returns (LockedStake[] memory);
}

contract KodiakPlugin is Plugin, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*----------  CONSTANTS  --------------------------------------------*/

    /*----------  STATE VARIABLES  --------------------------------------*/

    address public farm;

    /*----------  ERRORS ------------------------------------------------*/

    /*----------  FUNCTIONS  --------------------------------------------*/

    constructor(
        address _token, 
        address _voter, 
        address[] memory _assetTokens, 
        address[] memory _bribeTokens,
        address _vaultFactory,
        address _farm,
        string memory _protocol,
        string memory _name,
        string memory _vaultName
    )
        Plugin(
            _token, 
            _voter, 
            _assetTokens, 
            _bribeTokens,
            _vaultFactory,
            _protocol,
            _name,
            _vaultName
        )
    {
        farm = _farm;
    }

    function claimAndDistribute() 
        public
        override
        nonReentrant
    {
        super.claimAndDistribute();
        ICommunalFarm(farm).getReward();
        address bribe = getBribe();
        uint256 duration = IBribe(bribe).DURATION();
        for (uint256 i = 0; i < getBribeTokens().length; i++) {
            uint256 balance = IERC20(getBribeTokens()[i]).balanceOf(address(this));
            if (balance > duration) {
                IERC20(getBribeTokens()[i]).safeApprove(bribe, 0);
                IERC20(getBribeTokens()[i]).safeApprove(bribe, balance);
                IBribe(bribe).notifyRewardAmount(getBribeTokens()[i], balance);
            }
        }
    }

    function depositFor(address account, uint256 amount) 
        public
        override
        nonReentrant
    {
        super.depositFor(account, amount);
        ICommunalFarm(farm).withdrawLockedAll();
        uint256 balance = IERC20(getToken()).balanceOf(address(this));
        IERC20(getToken()).safeApprove(farm, 0);
        IERC20(getToken()).safeApprove(farm, balance);
        ICommunalFarm(farm).stakeLocked(balance, 0);
    }

    function withdrawTo(address account, uint256 amount) 
        public
        override
        nonReentrant
    {
        ICommunalFarm(farm).withdrawLockedAll(); 
        super.withdrawTo(account, amount);
        uint256 balance = IERC20(getToken()).balanceOf(address(this));
        if (balance > 0) {
            IERC20(getToken()).safeApprove(farm, 0);
            IERC20(getToken()).safeApprove(farm, balance);
            ICommunalFarm(farm).stakeLocked(balance, 0);
        }
    }

    /*----------  RESTRICTED FUNCTIONS  ---------------------------------*/

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    function getLockedLiquidity() public view returns (uint256) {
        return ICommunalFarm(farm).lockedLiquidityOf(address(this));
    }

    function getLockedStakes() public view returns (ICommunalFarm.LockedStake[] memory) {
        return ICommunalFarm(farm).lockedStakesOf(address(this));
    }

}

contract KodiakPluginFactory is Ownable {

    string public constant PROTOCOL = 'Kodiak';
    address public constant KDK = 0xfd27998fa0eaB1A6372Db14Afd4bF7c4a58C5364;
    address public constant XKDK = 0x414B50157a5697F14e91417C5275A7496DcF429D;
    address public constant REWARDS_VAULT_FACTORY = 0x2B6e40f65D82A0cB98795bC7587a71bfa49fBB2B;

    address public immutable VOTER;

    address public last_plugin;

    event Plugin__PluginCreated(address plugin);

    constructor(address _VOTER) {
        VOTER = _VOTER;
    }

    function createPlugin(
        address _lpToken,
        address _farm,
        address _token0,
        address _token1,
        address[] calldata _otherRewards,
        string memory _name, // ex 50WETH-50HONEY or 50WBTC-50HONEY or 50WBERA-50HONEY
        string memory _vaultName
    ) external returns (address) {

        address[] memory assetTokens = new address[](2);
        assetTokens[0] = _token0;
        assetTokens[1] = _token1;

        address[] memory bribeTokens = new address[](2 + _otherRewards.length);
        bribeTokens[0] = KDK;
        bribeTokens[1] = XKDK;
        for (uint256 i = 0; i < _otherRewards.length; i++) {
            bribeTokens[2 + i] = _otherRewards[i];
        }

        KodiakPlugin lastPlugin = new KodiakPlugin(
            _lpToken,
            VOTER,
            assetTokens,
            bribeTokens,
            REWARDS_VAULT_FACTORY,
            _farm,
            PROTOCOL,
            _name,
            _vaultName
        );
        last_plugin = address(lastPlugin);
        emit Plugin__PluginCreated(last_plugin);
        return last_plugin;
    }

}
