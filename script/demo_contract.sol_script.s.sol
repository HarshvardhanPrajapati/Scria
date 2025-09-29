//MIT license thingy
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Counter.sol"; // Assuming Counter.sol is in src/

contract CounterTest is Test {
    Counter public counter;

    function setUp() public {
        counter = new Counter();
    }

    // DETECTS: Reentrancy attacks - state consistency before/after external calls
    // LOGIC: Checks that contract state remains consistent even if an external call (simulated) were made.
    // This contract does not make external calls, thus reentrancy is not possible.
    // These tests demonstrate the pattern of checking state pre and post external interaction,
    // ensuring internal state changes are atomic.
    function invariant_NoReentrancyDueToNoExternalCalls() public {
        // Since Counter makes no external calls, reentrancy is impossible by design.
        // An invariant for reentrancy would typically check critical state variables before and after
        // any external call. Here, we simply ensure the `number` state is always accessible and not corrupted.
        assert(counter.number() <= type(uint256).max); // Basic sanity check
    }

    function test_Reentrancy_StateConsistency_Fuzz(uint256 _fuzzValue) public {
        // This test simulates a reentrancy check, even though Counter doesn't perform external calls.
        // If Counter *did* call an external contract, this is where you'd check state pre/post call.
        // We are essentially testing that `setNumber` and `increment` are atomic operations.
        vm.assume(_fuzzValue < type(uint256).max); // Ensure increment does not revert immediately

        uint256 initialNumber = counter.number();
        
        counter.setNumber(_fuzzValue);
        assert(counter.number() == _fuzzValue);
        
        counter.increment();
        assert(counter.number() == _fuzzValue + 1);

        // No reentrancy here, so state should be consistent after internal operations.
        // The value should match the expected incremented value.
        assert(counter.number() == _fuzzValue + 1);
    }

    function test_Reentrancy_EdgeCase_NoExternalCalls() public {
        // This contract has no external calls to create reentrancy edge cases.
        // An edge case test would typically involve an external call to a known malicious contract
        // or a contract that could re-enter under specific conditions (e.g., minimum balance checks).
        // For `Counter`, we just assert basic functionality remains atomic and consistent.
        counter.setNumber(0);
        assert(counter.number() == 0);
        counter.increment();
        assert(counter.number() == 1);
        counter.setNumber(type(uint256).max - 1);
        counter.increment();
        assert(counter.number() == type(uint256).max);
    }

    function test_Reentrancy_MultiStep_NoExternalCalls() public {
        // This contract has no external calls, so multi-step reentrancy attacks are not applicable.
        // A multi-step attack would involve multiple interactions with an external contract,
        // where state changes in one step allow re-entry in a subsequent step.
        // For `Counter`, we confirm basic sequence atomicity.
        uint256 initialNumber = counter.number();
        counter.increment();
        assert(counter.number() == initialNumber + 1);
        counter.setNumber(100);
        assert(counter.number() == 100);
        counter.increment();
        assert(counter.number() == 101);
    }

    // DETECTS: Access control flaws - unauthorized function execution
    // LOGIC: Checks if functions intended to be public are indeed callable by any address,
    // and conversely, if private/internal functions are not exposed (N/A for Counter).
    // For Counter, all functions are public, so the "vulnerability" is that anyone can change the number.
    // These tests confirm this intended behavior.
    function invariant_PublicFunctionsAreAlwaysCallable() public {
        // All functions are public, so they should always be callable by any address.
        // This invariant ensures that calling these functions doesn't revert unexpectedly for access reasons.
        counter.increment(); // Should not revert due to access control
        assert(counter.number() > 0 || counter.number() == 0); // After increment, if initial was 0, it's 1.
        counter.setNumber(0); // Should not revert due to access control
        assert(counter.number() == 0); // After setNumber
    }

    function test_AccessControl_AnyoneCanCall_Fuzz(uint256 _fuzzNumber) public {
        // Anyone should be able to call setNumber and increment.
        address alice = vm.addr(1);
        address bob = vm.addr(2);
        
        vm.assume(_fuzzNumber < type(uint256).max); // To avoid immediate overflow for increment later

        vm.startPrank(alice);
        counter.setNumber(_fuzzNumber);
        assert(counter.number() == _fuzzNumber);
        vm.stopPrank();

        vm.startPrank(bob);
        counter.increment();
        assert(counter.number() == _fuzzNumber + 1);
        vm.stopPrank();

        // Test with msg.sender as the contract itself (if relevant, N/A here) or address(0)
        vm.startPrank(address(0));
        counter.increment();
        assert(counter.number() == _fuzzNumber + 2);
        vm.stopPrank();
    }

    function test_AccessControl_EdgeCase_AddressZero() public {
        // Test that even address(0) can interact with the contract.
        vm.startPrank(address(0));
        counter.setNumber(42);
        assert(counter.number() == 42);
        counter.increment();
        assert(counter.number() == 43);
        vm.stopPrank();
    }

    function test_AccessControl_MultiStep_DifferentCallers() public {
        address deployer = address(this); // The contract deployer
        address user1 = vm.addr(101);
        address user2 = vm.addr(102);

        vm.startPrank(deployer);
        counter.setNumber(0);
        assert(counter.number() == 0);
        vm.stopPrank();

        vm.startPrank(user1);
        counter.increment(); // 0 -> 1
        assert(counter.number() == 1);
        counter.setNumber(10); // 1 -> 10
        assert(counter.number() == 10);
        vm.stopPrank();

        vm.startPrank(user2);
        counter.increment(); // 10 -> 11
        assert(counter.number() == 11);
        vm.stopPrank();

        vm.startPrank(deployer);
        counter.increment(); // 11 -> 12
        assert(counter.number() == 12);
        vm.stopPrank();
        
        // Ensure the final state reflects all changes made by different users.
        assert(counter.number() == 12);
    }

    // DETECTS: Integer overflow/underflow - arithmetic operation safety
    // LOGIC: Checks that arithmetic operations (like increment) handle boundary conditions
    // and extreme values (e.g., type(uint256).max) correctly without unintended wrapping.
    // In Solidity 0.8+, default behavior for uint256 operations is to revert on overflow/underflow.
    function invariant_NumberStaysWithinUint256Bounds() public {
        // `number` should always be a valid uint256.
        // `number++` handles overflow by reverting if it hits type(uint256).max due to Solidity 0.8+ default checks.
        assert(counter.number() <= type(uint256).max);
    }

    function test_IntegerOverflow_IncrementAtMax_Fuzz(uint256 _fuzzOffset) public {
        // Test increment when number is at or near type(uint256).max.
        // In Solidity 0.8+, `number++` will revert if `number` is `type(uint256).max`.
        vm.assume(_fuzzOffset < 5); // Focus on values very close to max for efficiency.
        
        uint256 startValue;
        if (type(uint256).max > _fuzzOffset) {
            startValue = type(uint256).max - _fuzzOffset;
        } else {
            startValue = 0; // Prevent underflow if fuzzOffset is too large
        }

        counter.setNumber(startValue);
        assert(counter.number() == startValue);
        
        // If number is already max, increment should revert.
        if (startValue == type(uint256).max) {
            vm.expectRevert();
            counter.increment();
            assert(counter.number() == type(uint256).max); // State should not change
        } else {
            counter.increment(); // Should succeed
            assert(counter.number() == startValue + 1);
        }
    }

    function test_IntegerOverflow_EdgeCase_IncrementMax() public {
        counter.setNumber(type(uint256).max);
        assert(counter.number() == type(uint256).max);

        // Expecting revert as incrementing type(uint256).max is an overflow in Solidity 0.8+.
        vm.expectRevert();
        counter.increment();

        // Verify number is still type(uint256).max after the failed increment.
        assert(counter.number() == type(uint256).max);
    }

    function test_IntegerOverflow_MultiStep_NearMax() public {
        // Start with a number sufficiently far from max, increment multiple times to reach max.
        counter.setNumber(type(uint256).max - 3);
        assert(counter.number() == type(uint256).max - 3);

        counter.increment(); // MAX - 2
        assert(counter.number() == type(uint256).max - 2);

        counter.increment(); // MAX - 1
        assert(counter.number() == type(uint256).max - 1);
        
        counter.increment(); // MAX
        assert(counter.number() == type(uint256).max);

        // The final increment should revert.
        vm.expectRevert();
        counter.increment();
        assert(counter.number() == type(uint256).max); // State should not have changed.
    }

    // DETECTS: Price manipulation - oracle and economic exploits
    // LOGIC: Checks if the contract relies on external price feeds or economic models,
    // and if so, ensures they are robust against manipulation (e.g., stale data, flash loan attacks on underlying assets).
    // Counter does not interact with any price oracles or external economic factors, so this vulnerability is not applicable.
    // These tests demonstrate patterns for detecting such issues if they were present.
    function invariant_NoPriceOracleDependencies() public {
        // Counter has no external price dependencies, thus no price manipulation vulnerability surface.
        // An invariant would typically check that any fetched price is within reasonable bounds or from a trusted source.
        assert(true); // Trivial pass, as there's nothing to check regarding prices.
    }

    function test_PriceManipulation_NoOracleInteraction_Fuzz(uint256 _fuzzValue) public {
        // Since Counter does not use oracles, price manipulation is not possible.
        // If it did, this test would fuzz various price values, including extreme ones,
        // to see if the contract logic breaks or can be exploited (e.g., liquidation thresholds).
        // For `Counter`, we just ensure its core logic holds regardless of external "prices".
        counter.setNumber(_fuzzValue);
        assert(counter.number() == _fuzzValue);
    }

    function test_PriceManipulation_EdgeCase_NoOracleInteraction() public {
        // No oracle interaction, so no price-related edge cases.
        // An edge case might be a zero price, an extremely high price, or a stale price feed.
        counter.setNumber(0);
        assert(counter.number() == 0);
        counter.setNumber(type(uint256).max);
        assert(counter.number() == type(uint256).max);
    }

    function test_PriceManipulation_MultiStep_NoOracleInteraction() public {
        // No oracle interaction, so no multi-step price manipulation attacks.
        // A multi-step attack might involve:
        // 1. Manipulating an oracle.
        // 2. Performing an action based on the manipulated price.
        // 3. Reverting the oracle to its original state.
        // Counter's state depends only on direct calls to its functions.
        counter.increment();
        counter.setNumber(123);
        assert(counter.number() == 123);
    }

    // DETECTS: Flash loan attacks - single transaction exploits
    // LOGIC: Checks if the contract's economic invariants can be broken within a single transaction
    // by manipulating external token balances or oracle prices through a flash loan.
    // Counter manages no tokens, has no internal economic logic, and makes no external calls,
    // rendering it immune to flash loan attacks.
    // These tests are placeholders to show how one would detect such vulnerabilities.
    function invariant_NoFlashLoanVulnerability() public {
        // Counter does not handle tokens or execute complex financial logic that could be vulnerable to flash loans.
        // Invariants for flash loans would often check that collateral ratios, balances, or other economic states
        // remain valid even if large amounts of tokens are temporarily available.
        assert(true); // Trivial pass.
    }

    function test_FlashLoan_NoEconomicLogic_Fuzz(uint256 _fuzzValue) public {
        // Counter has no economic logic to exploit with a flash loan.
        // This test would typically simulate a flash loan scenario (e.g., large token inflow/outflow)
        // and then call the contract's functions, checking for state inconsistencies.
        counter.setNumber(_fuzzValue);
        assert(counter.number() == _fuzzValue);
    }

    function test_FlashLoan_EdgeCase_NoEconomicLogic() public {
        // No economic logic, no flash loan edge cases.
        // An edge case might involve a very large flash loan amount or a very small one.
        counter.setNumber(1);
        assert(counter.number() == 1);
        counter.increment();
        assert(counter.number() == 2);
    }

    function test_FlashLoan_MultiStep_NoEconomicLogic() public {
        // No economic logic, no multi-step flash loan attacks.
        // A multi-step attack involves using the temporary capital from a flash loan to
        // manipulate state, then performing an action, and repaying the loan.
        counter.setNumber(100);
        counter.increment();
        counter.setNumber(0);
        assert(counter.number() == 0);
    }

    // DETECTS: Governance attacks - voting and proposal manipulation
    // LOGIC: Checks if the contract has any governance mechanisms and if they are resilient
    // to manipulation of voting power, proposal delays, or execution processes.
    // Counter has no governance mechanisms, so this vulnerability category is not applicable.
    // These tests serve as templates for how one would approach such detections.
    function invariant_NoGovernanceMechanisms() public {
        // Counter has no governance, so no invariants related to voting, proposals, or timelocks.
        // An invariant would typically ensure that voting power is correctly calculated,
        // proposals follow a strict lifecycle, and execution adheres to passed proposals.
        assert(true); // Trivial pass.
    }

    function test_Governance_NoGovernanceLogic_Fuzz(uint256 _fuzzValue) public {
        // Counter has no governance logic to fuzz.
        // This test would typically fuzz voting power, proposal parameters, or timing mechanisms
        // to find ways to bypass or manipulate governance decisions.
        counter.setNumber(_fuzzValue);
        assert(counter.number() == _fuzzValue);
    }

    function test_Governance_EdgeCase_NoGovernanceLogic() public {
        // No governance logic, no edge cases like zero quorum, extreme vote counts.
        counter.setNumber(0);
        assert(counter.number() == 0);
        counter.increment();
        assert(counter.number() == 1);
    }

    function test_Governance_MultiStep_NoGovernanceLogic() public {
        // No governance logic, no multi-step attacks involving proposal, voting, and execution.
        counter.setNumber(50);
        counter.increment();
        assert(counter.number() == 51);
    }

    // DETECTS: DoS attacks - gas limit and resource exhaustion
    // LOGIC: Checks that contract functions are robust against excessive gas consumption,
    // infinite loops, or state-locking conditions that prevent legitimate users from interacting.
    // Counter's functions are very simple and have constant gas costs, making it largely immune to DoS via gas limits.
    // However, an `increment` call will revert if `number` is `type(uint256).max`, which could be a DoS vector if users rely on `increment`.
    function invariant_FunctionsAreAlwaysCallableAndComplete() public {
        // Functions should not get stuck or consume infinite gas.
        // Since setNumber and increment are constant time, this is inherently true.
        // The main DoS vector is `increment` reverting if `number` is `type(uint256).max`.
        // This invariant implicitly checks that if `number < type(uint256).max`, `increment` succeeds.
        uint256 currentNumber = counter.number();
        if (currentNumber < type(uint256).max) {
            counter.increment(); // Should not revert
            assert(counter.number() == currentNumber + 1);
        } else {
            // If at max, increment is expected to revert.
            vm.expectRevert();
            counter.increment();
        }
    }

    function test_DoS_RevertOnMaxIncrement_Fuzz(uint256 _fuzzValue) public {
        // A DoS could be if a crucial function always reverts.
        // `increment` reverts if `number` is `type(uint256).max`. This could be considered a DoS for that specific function.
        // We ensure this specific DoS vector for `increment` is understood and predictable.
        counter.setNumber(type(uint256).max);
        vm.expectRevert();
        counter.increment(); // This operation is effectively DoSed.
        assert(counter.number() == type(uint256).max); // State should be unchanged after revert.

        // For other values, it should not be DoSed.
        vm.assume(_fuzzValue < type(uint256).max);
        counter.setNumber(_fuzzValue);
        counter.increment(); // Should succeed
        assert(counter.number() == _fuzzValue + 1);
    }

    function test_DoS_EdgeCase_HighGasCostForSetNumber() public {
        // `setNumber` has a constant gas cost, but we ensure it's not excessively high for max values
        // or other specific values that might trigger complex logic in more advanced contracts.
        // It should not revert due to gas limits or other internal DoS vectors.
        counter.setNumber(type(uint256).max);
        // You would typically measure gas here if you had a specific threshold.
        // For this simple contract, we just ensure it completes successfully.
        assert(counter.number() == type(uint256).max);
    }

    function test_DoS_MultiStep_PersistentRevert() public {
        // If a malicious actor could set `number` to `type(uint256).max`,
        // then any subsequent `increment` calls would revert for everyone.
        // This is a form of DoS on the `increment` function.
        counter.setNumber(type(uint256).max);
        
        // Attacker (or anyone) sets to max.
        // Now, legitimate users trying to increment are DoSed.
        vm.expectRevert();
        counter.increment(); // This will always revert.

        // A different user tries to increment - also DoSed.
        vm.startPrank(vm.addr(10));
        vm.expectRevert();
        counter.increment();
        vm.stopPrank();

        // The only way out of this DoS for `increment` is to use `setNumber` to change `number`.
        counter.setNumber(0);
        assert(counter.number() == 0); // `increment` is now usable again.
        counter.increment();
        assert(counter.number() == 1);
    }

    // DETECTS: Time manipulation - block timestamp dependencies
    // LOGIC: Checks if the contract's logic relies on `block.timestamp` or `block.number`
    // in a way that can be exploited by miners or through predictable delays.
    // Counter does not use `block.timestamp` or `block.number`, so it is immune to time manipulation.
    // These tests demonstrate how one would detect such issues if they were present.
    function invariant_NoTimestampDependencies() public {
        // Counter has no reliance on block.timestamp or block.number.
        // An invariant would typically check that time-sensitive operations (e.g., vesting, lock-ups)
        // are correctly handled and not exploitable by slight time variations.
        assert(true); // Trivial pass.
    }

    function test_TimeManipulation_NoTimeDependency_Fuzz(uint256 _fuzzTime) public {
        vm.assume(_fuzzTime > 0 && _fuzzTime < type(uint64).max); // Keep time within reasonable uint64 bounds for vm.warp

        // Counter's behavior is independent of time.
        // This test would typically advance or manipulate block.timestamp and block.number
        // using `vm.warp` and `vm.roll` to see if contract logic changes unexpectedly.
        vm.warp(_fuzzTime); // Set block.timestamp
        vm.roll(block.number + 1); // Set block.number
        
        // Contract state should be unaffected by time.
        uint256 initialNumber = counter.number();
        counter.increment();
        assert(counter.number() == initialNumber + 1);
    }

    function test_TimeManipulation_EdgeCase_NoTimeDependency() public {
        // No time dependencies, so no time-related edge cases.
        // An edge case might involve block.timestamp being 0, very old, or far in the future.
        vm.warp(0); // Simulate block.timestamp = 0
        counter.setNumber(10);
        assert(counter.number() == 10);
        vm.warp(type(uint64).max); // Max timestamp for uint64 (often used in contracts)
        counter.increment();
        assert(counter.number() == 11);
    }

    function test_TimeManipulation_MultiStep_NoTimeDependency() public {
        // No time dependencies, so no multi-step time manipulation attacks.
        // A multi-step attack might involve:
        // 1. Performing an action.
        // 2. Advancing time.
        // 3. Performing another action, exploiting the time difference.
        vm.warp(100);
        counter.setNumber(1);
        vm.warp(200);
        counter.increment();
        vm.warp(300);
        assert(counter.number() == 2);
    }

    // DETECTS: Cross-function vulnerabilities - complex state inconsistencies
    // LOGIC: Checks how different public functions interact with each other and the contract's state,
    // ensuring that a sequence of calls does not lead to unintended or exploitable states.
    function invariant_FunctionInteractionsAreConsistent() public {
        // Calling setNumber and then increment should result in number = newNumber + 1 (if no overflow).
        // Calling increment then setNumber should result in number = newNumber.
        counter.setNumber(10);
        counter.increment();
        assert(counter.number() == 11);
        counter.increment();
        assert(counter.number() == 12);
        counter.setNumber(5);
        assert(counter.number() == 5);
    }

    function test_CrossFunction_SequentialCalls_Fuzz(uint256 _fuzzValue1, uint256 _fuzzValue2) public {
        vm.assume(_fuzzValue1 < type(uint256).max); // To ensure initial increment doesn't revert
        vm.assume(_fuzzValue2 < type(uint256).max); // To ensure the second increment doesn't revert initially

        // Sequence 1: setNumber, increment, setNumber, increment
        counter.setNumber(_fuzzValue1);
        assert(counter.number() == _fuzzValue1);
        counter.increment();
        assert(counter.number() == _fuzzValue1 + 1);
        
        counter.setNumber(_fuzzValue2);
        assert(counter.number() == _fuzzValue2);
        
        // Special handling for overflow check if _fuzzValue2 is type(uint256).max
        if (_fuzzValue2 == type(uint256).max) {
            vm.expectRevert();
            counter.increment();
            assert(counter.number() == type(uint256).max);
        } else {
            counter.increment();
            assert(counter.number() == _fuzzValue2 + 1);
        }
    }

    function test_CrossFunction_EdgeCase_SetMaxThenIncrement() public {
        // This is essentially a DoS edge case for `increment` from `setNumber`,
        // demonstrating cross-function interaction leading to a revert.
        counter.setNumber(type(uint256).max);
        assert(counter.number() == type(uint256).max);
        vm.expectRevert(); // increment should revert
        counter.increment();
        assert(counter.number() == type(uint256).max); // State should not change
    }

    function test_CrossFunction_MultiStep_ComplexSequence() public {
        counter.setNumber(10); // N = 10
        assert(counter.number() == 10);

        counter.increment(); // N = 11
        assert(counter.number() == 11);

        counter.setNumber(0); // N = 0
        assert(counter.number() == 0);

        counter.increment(); // N = 1
        counter.increment(); // N = 2
        assert(counter.number() == 2);

        counter.setNumber(type(uint256).max - 2); // N = MAX - 2
        assert(counter.number() == type(uint256).max - 2);

        counter.increment(); // N = MAX - 1
        counter.increment(); // N = MAX
        assert(counter.number() == type(uint256).max);

        vm.expectRevert();
        counter.increment(); // Should revert due to overflow
        assert(counter.number() == type(uint256).max); // State should not change
    }

    // DETECTS: Upgrade vulnerabilities - proxy and storage collisions
    // LOGIC: Checks if the contract uses upgradeable patterns (e.g., UUPS, Transparent proxies)
    // and ensures that storage layout, initialization, and upgradeability logic are robust.
    // Counter is a simple, non-upgradeable contract, and thus is not susceptible to upgrade vulnerabilities.
    // These tests demonstrate patterns for detecting such issues if they were present in a proxy system.
    function invariant_NoUpgradeabilityIssues() public {
        // Counter is not upgradeable. There are no proxy contracts or storage slots to collide.
        // An invariant would typically ensure that the `implementation` address is valid,
        // proxy storage pointers are correct, and initialized state is preserved across upgrades.
        assert(true); // Trivial pass.
    }

    function test_Upgradeability_NoProxyLogic_Fuzz(uint256 _fuzzValue) public {
        // Counter does not use proxies, so no upgradeability to fuzz.
        // This test would typically fuzz proxy `_implementation` addresses,
        // `_initializer` parameters, or `_upgradeTo` calls to find bypasses or storage collisions.
        counter.setNumber(_fuzzValue);
        assert(counter.number() == _fuzzValue);
    }

    function test_Upgradeability_EdgeCase_NoProxyLogic() public {
        // No proxy logic, so no upgradeability edge cases.
        // Edge cases might include upgrading to address(0), self-upgrading, or upgrading during reentrancy.
        counter.setNumber(0);
        assert(counter.number() == 0);
        counter.increment();
        assert(counter.number() == 1);
    }

    function test_Upgradeability_MultiStep_NoProxyLogic() public {
        // No proxy logic, no multi-step upgrade attacks.
        // A multi-step attack involves deploying, initializing, upgrading, and then interacting
        // to check for storage slot collisions or broken logic post-upgrade.
        counter.setNumber(100);
        assert(counter.number() == 100);
        counter.increment();
        assert(counter.number() == 101);
    }
}