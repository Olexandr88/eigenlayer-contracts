// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/test/integration/IntegrationChecks.t.sol";
import "src/test/integration/User.t.sol";

contract Integration_Deposit_Delegate_UpdateBalance is IntegrationCheckUtils {

    /// Generates a random stake and operator. The staker:
    /// 1. deposits all assets into strategies
    /// 2. delegates to an operator
    /// 3. queues a withdrawal for a ALL shares
    /// 4. updates their balance randomly
    /// 5. completes the queued withdrawal as tokens
    function testFuzz_deposit_delegate_updateBalance_completeAsTokens(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _assetTypes: HOLDS_ETH,
            _userTypes: DEFAULT | ALT_METHODS
        });

        /// 0. Create an operator and staker with some underlying assets
        (
            User staker,
            IStrategy[] memory strategies, 
            uint[] memory tokenBalances
        ) = _newRandomStaker();
        (User operator, ,) = _newRandomOperator();
        uint[] memory shares = _calculateExpectedShares(strategies, tokenBalances);

        assert_HasNoDelegatableShares(staker, "staker should not have delegatable shares before depositing");
        assertFalse(delegationManager.isDelegated(address(staker)), "staker should not be delegated");

        /// 1. Deposit into strategies
        staker.depositIntoEigenlayer(strategies, tokenBalances);
        check_Deposit_State(staker, strategies, shares);

        /// 2. Delegate to an operator
        staker.delegateTo(operator);
        check_Delegation_State(staker, operator, strategies, shares);

        /// 3. Queue withdrawals for ALL shares
        IDelegationManager.Withdrawal[] memory withdrawals = staker.queueWithdrawals(strategies, shares);
        bytes32[] memory withdrawalRoots = _getWithdrawalHashes(withdrawals);
        check_QueuedWithdrawal_State(staker, operator, strategies, shares, withdrawals, withdrawalRoots);

        // Generate a random balance update:
        // - For LSTs, the tokenDelta is positive tokens minted to the staker
        // - For ETH, the tokenDelta is a positive or negative change in beacon chain balance
        (
            int[] memory tokenDeltas, 
            int[] memory stakerShareDeltas,
            int[] memory operatorShareDeltas
        ) = _randBalanceUpdate(staker, strategies);

        // 4. Update LST balance by depositing, and beacon balance by submitting a proof
        staker.updateBalances(strategies, tokenDeltas);
        assert_Snap_Delta_StakerShares(staker, strategies, stakerShareDeltas, "staker should have applied deltas correctly");
        assert_Snap_Delta_OperatorShares(operator, strategies, operatorShareDeltas, "operator should have applied deltas correctly");

        // 5. Complete queued withdrawals as tokens
        // Fast forward to when we can complete the withdrawal
        cheats.roll(block.number + delegationManager.withdrawalDelayBlocks());
        for (uint i = 0; i < withdrawals.length; i++) {
            uint[] memory expectedTokens = _calculateExpectedTokens(staker, withdrawals[i].strategies, withdrawals[i].shares);
            IERC20[] memory tokens = staker.completeWithdrawalAsTokens(withdrawals[i]);
            check_Withdrawal_AsTokens_BalanceUpdate_State(staker, operator, withdrawals[i], strategies, shares, tokens, expectedTokens);
        }

        // Final state checks
        assertEq(address(operator), delegationManager.delegatedTo(address(staker)), "staker should still be delegated to operator");
        assert_NoWithdrawalsPending(withdrawalRoots, "all withdrawals should be removed from pending");
    }

    function testFuzz_deposit_delegate_updateBalance_completeAsShares(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _assetTypes: HOLDS_ETH,
            _userTypes: DEFAULT | ALT_METHODS
        });

        /// 0. Create an operator and staker with some underlying assets
        (
            User staker,
            IStrategy[] memory strategies, 
            uint[] memory tokenBalances
        ) = _newRandomStaker();
        (User operator, ,) = _newRandomOperator();
        uint[] memory shares = _calculateExpectedShares(strategies, tokenBalances);

        assert_HasNoDelegatableShares(staker, "staker should not have delegatable shares before depositing");
        assertFalse(delegationManager.isDelegated(address(staker)), "staker should not be delegated");

        /// 1. Deposit into strategies
        staker.depositIntoEigenlayer(strategies, tokenBalances);
        check_Deposit_State(staker, strategies, shares);

        /// 2. Delegate to an operator
        staker.delegateTo(operator);
        check_Delegation_State(staker, operator, strategies, shares);

        /// 3. Queue withdrawals for ALL shares
        IDelegationManager.Withdrawal[] memory withdrawals = staker.queueWithdrawals(strategies, shares);
        bytes32[] memory withdrawalRoots = _getWithdrawalHashes(withdrawals);
        check_QueuedWithdrawal_State(staker, operator, strategies, shares, withdrawals, withdrawalRoots);

        // Generate a random balance update:
        // - For LSTs, the tokenDelta is positive tokens minted to the staker
        // - For ETH, the tokenDelta is a positive or negative change in beacon chain balance
        (
            int[] memory tokenDeltas, 
            int[] memory stakerShareDeltas,
            int[] memory operatorShareDeltas
        ) = _randBalanceUpdate(staker, strategies);

        // 4. Update LST balance by depositing, and beacon balance by submitting a proof
        staker.updateBalances(strategies, tokenDeltas);
        assert_Snap_Delta_StakerShares(staker, strategies, stakerShareDeltas, "staker should have applied deltas correctly");
        assert_Snap_Delta_OperatorShares(operator, strategies, operatorShareDeltas, "operator should have applied deltas correctly");

        // 5. Complete queued withdrawals as shares
        // Fast forward to when we can complete the withdrawal
        cheats.roll(block.number + delegationManager.withdrawalDelayBlocks());
        for (uint i = 0; i < withdrawals.length; i++) {
            staker.completeWithdrawalAsShares(withdrawals[i]);
            check_Withdrawal_AsShares_BalanceUpdate_State(staker, operator, withdrawals[i], strategies, shares);
        }

        // Final state checks
        assertEq(address(operator), delegationManager.delegatedTo(address(staker)), "staker should still be delegated to operator");
        assert_NoWithdrawalsPending(withdrawalRoots, "all withdrawals should be removed from pending");
    }
}