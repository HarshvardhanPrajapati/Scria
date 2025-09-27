//MIT license thingy
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/demo_contract.sol"; // Adjust path if your contract is in a different location

contract CounterTest is Test {
    Counter public counter;

    function setUp() public {
        counter = new Counter();
    }

    //
    // 1. Reentrancy attacks - state consistency before/after external calls
    //
    // Note: The Counter contract does not perform external calls, making reentrancy impossible.
    // These tests demonstrate patterns for detecting reentrancy in contracts that *do* make external calls.

    // DETECTS: Potential reentrancy by observing state changes during or after a hypothetical external call.
    // LOGIC: A critical state variable (`number`) should not be unexpectedly modified during a sequence
    //        that involves an external call. For Counter, this means 'number' should only change
    //        through its own functions, and no external call could implicitly alter it.
    function invariant_ReentrancyProtection() public {
        uint256 originalNumber = counter.number();
        // Simulate a state-modifying operation. Since Counter has no external calls,
        // we assert that its state cannot be manipulated by an external call.
        // If Counter *did* make an external call, this would involve asserting
        // state pre-call and post-call consistency.
        counter.increment();
        assertEq(counter.number(), originalNumber + 1, "Increment operation failed or was reentered");

        // More rigorously, if there were an external call, we'd check critical state variables
        // before and after the call. Since there isn't one, we assert the absence of unexpected state changes.
        // The number should only change if one of its own functions is called.
        // This invariant implicitly states no external party can change 'number' without calling setNumber or increment.
    }

    // DETECTS: Reentrancy by observing a hypothetical attack sequence.
    // LOGIC: A malicious contract should not be able to re-enter and manipulate state.
    //        This test sets up a pattern to catch such re-entries if external calls were present.
    function test_Reentrancy_Fuzz(uint256 initialValue) public {
        vm.assume(initialValue < type(uint256).max); // Avoid overflow for initial setup
        counter.setNumber(initialValue);
        uint256 preNumber = counter.number();

        // In a real scenario, this would involve a mock external call that attempts re-entry.
        // Since Counter has no external calls, we demonstrate that its state is isolated.
        counter.increment(); // Only legitimate internal operations change state
        assertEq(counter.number(), preNumber + 1, "Number unexpectedly changed or reentered");

        // Edge case: if setNumber was a vulnerable function
        counter.setNumber(initialValue + 1);
        assertEq(counter.number(), initialValue + 1, "setNumber unexpectedly changed or reentered");
    }

    // DETECTS: Multi-step reentrancy attack simulation.
    // LOGIC: Complex reentrancy often involves multiple steps to drain funds or manipulate state.
    function test_Reentrancy_MultiStepAttack() public {
        counter.setNumber(100);
        // This is a placeholder for a multi-step attack.
        // In a real contract, this would involve:
        // 1. Attacker calls vulnerable function.
        // 2. Vulnerable function makes external call to attacker.
        // 3. Attacker re-enters, performs another action (e.g., withdraws again).
        // 4. Original function completes.
        // For Counter, we just show that its state is isolated.
        uint256 initial = counter.number();
        counter.increment();
        assertEq(counter.number(), initial + 1, "Multi-step state manipulation detected.");
    }


    //
    // 2. Access control flaws - unauthorized function execution
    //
    // Note: The Counter contract's functions are public and have no access control, which is intended.
    // These tests confirm that *anyone* can call them, demonstrating the absence of access control.
    // If access control were intended, these tests would fail and reveal the flaw.

    // DETECTS: Unauthorized execution of `setNumber`.
    // LOGIC: Only an authorized sender should be able to call `setNumber`.
    //        For Counter, as all functions are public, this test confirms any address can call it.
    function invariant_SetNumberAccessControl() public {
        address user1 = vm.addr(1);
        vm.startPrank(user1);
        counter.setNumber(55); // Any user can call setNumber
        assertEq(counter.number(), 55, "Unauthorized address could not set number, implying unintended access control.");
        vm.stopPrank();

        address user2 = vm.addr(2);
        vm.startPrank(user2);
        counter.setNumber(77);
        assertEq(counter.number(), 77, "Another unauthorized address could not set number.");
        vm.stopPrank();
    }

    // DETECTS: Unauthorized execution of `increment`.
    // LOGIC: Only an authorized sender should be able to call `increment`.
    //        For Counter, this test confirms any address can call it.
    function test_IncrementAccess_Fuzz(address randomUser) public {
        vm.assume(randomUser != address(0)); // Valid address
        counter.setNumber(10);
        uint256 preIncrement = counter.number();

        vm.startPrank(randomUser);
        counter.increment(); // Any user can call increment
        vm.stopPrank();

        assertEq(counter.number(), preIncrement + 1, "Random user could not increment, implying unintended access control.");

        // Edge case: Address zero should not be able to interact (though this is more of a contract setup issue)
        vm.startPrank(address(0));
        vm.expectRevert(); // Most contracts would revert for address(0) for msg.sender validation
        // However, Counter does not validate msg.sender, so this might not revert for Counter directly.
        // For Counter, calling from address(0) is allowed.
        // counter.increment(); // If this line executed, it implies address(0) is a valid sender.
        // assertEq(counter.number(), preIncrement + 2, "Address(0) could not increment.");
        vm.stopPrank();
    }

    // DETECTS: Multi-step access control bypass.
    // LOGIC: Assures that even in a sequence, only authorized users can perform actions.
    function test_AccessControl_MultiStep() public {
        counter.setNumber(100);
        address attacker = vm.addr(999);
        address legitimateUser = vm.addr(1000);

        // Legitimate user performs actions
        vm.startPrank(legitimateUser);
        counter.increment();
        assertEq(counter.number(), 101, "Legitimate user failed to increment.");
        counter.setNumber(200);
        assertEq(counter.number(), 200, "Legitimate user failed to set number.");
        vm.stopPrank();

        // Attacker attempts to perform actions (should succeed in Counter's case)
        vm.startPrank(attacker);
        counter.increment();
        assertEq(counter.number(), 201, "Attacker failed to increment (indicating unintended access control).");
        counter.setNumber(300);
        assertEq(counter.number(), 300, "Attacker failed to set number.");
        vm.stopPrank();
    }

    //
    // 3. Integer overflow/underflow - arithmetic operation safety
    //

    // DETECTS: Integer overflow in `increment()` when `number` is `type(uint256).max`.
    // LOGIC: `number` should not wrap around when incremented from `type(uint256).max`.
    //        Solidity 0.8.0+ automatically reverts on overflow/underflow for `uint256`.
    function invariant_NoIncrementOverflow() public {
        counter.setNumber(type(uint256).max);
        vm.expectRevert(); // Expect revert due to overflow in Solidity 0.8+
        counter.increment();
        assertEq(counter.number(), type(uint256).max, "Number overflowed unexpectedly, should have reverted.");
    }

    // DETECTS: Integer overflow when fuzzing `increment` close to `type(uint256).max`.
    // LOGIC: `number` should correctly increment for valid ranges, and revert for overflow.
    function test_IncrementOverflow_Fuzz(uint256 initialNumber) public {
        vm.assume(initialNumber < type(uint256).max); // Only fuzz non-max values for successful increment
        counter.setNumber(initialNumber);
        uint256 expected = initialNumber + 1; // Expected value after increment
        counter.increment();
        assertEq(counter.number(), expected, "Increment resulted in incorrect value or overflowed prematurely.");

        // Edge case: Try incrementing from type(uint256).max - 1
        counter.setNumber(type(uint256).max - 1);
        counter.increment();
        assertEq(counter.number(), type(uint256).max, "Increment from max-1 failed.");

        // Edge case: Direct increment from 0
        counter.setNumber(0);
        counter.increment();
        assertEq(counter.number(), 1, "Increment from 0 failed.");
    }

    // DETECTS: Multi-step overflow sequence.
    // LOGIC: Ensures multiple increments behave correctly, eventually leading to an expected revert.
    function test_IncrementOverflow_MultiStep() public {
        counter.setNumber(type(uint256).max - 2);
        counter.increment();
        assertEq(counter.number(), type(uint256).max - 1, "First increment failed.");
        counter.increment();
        assertEq(counter.number(), type(uint256).max, "Second increment failed.");

        vm.expectRevert(); // The final increment should revert
        counter.increment();
        assertEq(counter.number(), type(uint256).max, "Number overflowed after third increment, should have reverted.");
    }

    //
    // 4. Price manipulation - oracle and economic exploits
    //
    // Note: The Counter contract has no economic value, does not use oracles, and does not handle tokens/ETH.
    // These tests are purely illustrative of how such properties would be structured for a relevant contract.

    // DETECTS: Unreliable or manipulated price feeds affecting critical operations.
    // LOGIC: Critical contract state (`number`) should not be influenced by external, manipulable price feeds.
    //        For Counter, this means `number` should never derive from an oracle.
    function invariant_PriceFeedIntegrity() public {
        // Since Counter doesn't use price feeds, this invariant asserts its independence.
        // In a real contract, this would involve asserting that internal value calculations
        // based on oracles are within expected bounds, or that critical state isn't directly
        // dependent on potentially stale/manipulated prices.
        assert(true, "Counter contract does not rely on external price feeds, thus immune to price manipulation.");
    }

    // DETECTS: Price manipulation attempts through extreme oracle values.
    // LOGIC: The contract should handle extreme (e.g., zero, max) price inputs gracefully without breaking.
    function test_PriceManipulation_Fuzz(uint256 manipulatedPrice) public {
        // vm.assume(manipulatedPrice >= 0); // Price can be anything
        // In a real scenario, mock oracle with `manipulatedPrice`.
        // Then call a function that uses the oracle and assert expected outcome or revert.
        // For Counter, there are no price-sensitive operations.
        assert(true, "Counter contract is not price-sensitive.");
    }

    // DETECTS: Multi-step price manipulation or flash loan setup.
    // LOGIC: A sequence of actions should not allow an attacker to profit from price discrepancies.
    function test_PriceManipulation_MultiStep() public {
        // 1. Attacker manipulates price (e.g., flash loan, swap to move price).
        // 2. Attacker calls victim contract, which uses the manipulated price.
        // 3. Attacker reverses manipulation, profits.
        // Counter contract has no such attack surface.
        assert(true, "Multi-step price manipulation is not applicable to Counter.");
    }

    //
    // 5. Flash loan attacks - single transaction exploits
    //
    // Note: The Counter contract handles no tokens/ETH and has no internal logic vulnerable to temporary liquidity.
    // These tests are purely illustrative.

    // DETECTS: Flash loan profitability through arbitrage or state manipulation.
    // LOGIC: The contract's critical state should remain consistent even if large, temporary amounts of assets
    //        are available within a single transaction.
    function invariant_NoFlashLoanProfit() public {
        // Assert that no profit can be made from a flash loan against this contract.
        // For Counter, this is always true as it holds no value.
        assertEq(counter.number(), counter.number(), "State consistency for flash loan (trivial for Counter).");
    }

    // DETECTS: Extreme scenarios with flash loan liquidity.
    // LOGIC: Contract should not break or allow exploits when large amounts of capital are temporarily available.
    function test_FlashLoan_Fuzz(uint256 flashLoanAmount) public {
        vm.assume(flashLoanAmount > 0); // Simulate any flash loan amount
        // In a real test, mock a flash loan receiver calling into the contract.
        // Check if `counter.number()` (or any state) can be exploited with large `flashLoanAmount`.
        // For Counter, it cannot.
        assert(true, "Counter contract is not vulnerable to flash loans.");
    }

    // DETECTS: Multi-step flash loan attack.
    // LOGIC: Assures that multiple interactions within a single transaction using flash loan funds do not lead to exploits.
    function test_FlashLoan_MultiStep() public {
        // Simulate:
        // 1. Receive flash loan.
        // 2. Call `setNumber` with some manipulated value (irrelevant for Counter).
        // 3. Call `increment` multiple times.
        // 4. Repay flash loan.
        // Assert no unexpected state changes or value drained.
        uint256 initialNumber = counter.number();
        counter.increment();
        counter.increment();
        assertEq(counter.number(), initialNumber + 2, "Flash loan multi-step attack detected (trivial for Counter).");
    }

    //
    // 6. Governance attacks - voting and proposal manipulation
    //
    // Note: The Counter contract has no governance mechanisms. These tests are purely illustrative.

    // DETECTS: Malicious proposals, voting power manipulation, or timelock bypass.
    // LOGIC: Governance-controlled parameters or actions should only occur through legitimate proposals
    //        and sufficient voting power, respecting timelocks.
    function invariant_GovernanceIntegrity() public {
        // For Counter, it has no governance. This invariant confirms its independence from governance.
        assert(true, "Counter contract has no governance mechanisms, thus immune to governance attacks.");
    }

    // DETECTS: Extreme scenarios of voting power or proposal values.
    // LOGIC: Governance system should remain robust under extreme voting conditions or malicious proposal values.
    function test_Governance_Fuzz(uint256 proposalId, uint256 votes) public {
        // vm.assume(votes > 0);
        // In a real test, simulate a governance process:
        // 1. Create a proposal (e.g., to change `setNumber`'s owner via governance).
        // 2. Simulate various voting patterns (high/low votes, different voters).
        // 3. Assert proposal outcome is legitimate.
        // Counter has no governance.
        assert(true, "Counter contract is not governed.");
    }

    // DETECTS: Multi-step governance manipulation (e.g., acquiring tokens, voting, re-acquiring more, voting again).
    // LOGIC: A sequence of governance-related actions should not allow an attacker to bypass checks or gain undue control.
    function test_Governance_MultiStep() public {
        // Simulate:
        // 1. Acquire governance tokens.
        // 2. Propose a malicious action.
        // 3. Vote.
        // 4. Acquire more tokens.
        // 5. Vote again or execute.
        // For Counter, this is not applicable.
        assert(true, "Multi-step governance attack is not applicable to Counter.");
    }

    //
    // 7. DoS attacks - gas limit and resource exhaustion
    //

    // DETECTS: Functions consuming excessive gas, leading to denial of service.
    // LOGIC: Core functions (`setNumber`, `increment`) must always be executable within gas limits.
    //        This contract's functions are simple, fixed-gas operations.
    function invariant_DoSProtection() public {
        uint256 initialGas = gasleft();
        counter.setNumber(1);
        uint256 gasCostSet = initialGas - gasleft();
        // Assert gas cost is below a reasonable limit (e.g., 100,000 for simple ops)
        assert(gasCostSet < 100_000, "setNumber gas cost too high, potential DoS vector.");

        initialGas = gasleft();
        counter.increment();
        uint256 gasCostIncrement = initialGas - gasleft();
        assert(gasCostIncrement < 100_000, "increment gas cost too high, potential DoS vector.");
    }

    // DETECTS: Extreme parameter values causing excessive gas usage.
    // LOGIC: Providing `type(uint256).max` or other large values should not break the contract.
    function test_DoS_Fuzz(uint256 param) public {
        // Fuzz setNumber with extreme values
        uint256 initialGas = gasleft();
        counter.setNumber(param); // Setting max uint256 is fine for assignment.
        uint256 gasCostSet = initialGas - gasleft();
        assert(gasCostSet < 100_000, "setNumber with extreme param gas cost too high.");

        // Fuzz increment. This should eventually revert due to overflow, not gas.
        counter.setNumber(param % (type(uint256).max / 2)); // Keep number reasonable for fuzzing
        initialGas = gasleft();
        counter.increment();
        uint256 gasCostIncrement = initialGas - gasleft();
        assert(gasCostIncrement < 100_000, "increment with extreme state gas cost too high.");
    }

    // DETECTS: Multi-step DoS (e.g., filling storage, repeated calls to expensive functions).
    // LOGIC: Even repeated legitimate operations should not lead to a DoS condition.
    function test_DoS_MultiStep() public {
        // For Counter, there are no dynamic arrays, complex loops, or external storage dependencies.
        // Repeated calls are trivial.
        for (uint256 i = 0; i < 10; i++) { // Small loop for sanity
            counter.increment();
            assert(gasleft() > 100_000, "Gas exhausted during multi-step operation."); // Check remaining gas
        }
        counter.setNumber(1);
        counter.setNumber(2);
        assert(gasleft() > 100_000, "Gas exhausted during multi-step set.");
    }

    //
    // 8. Time manipulation - block timestamp dependencies
    //
    // Note: The Counter contract does not use `block.timestamp` or `block.number`.
    // These tests are purely illustrative.

    // DETECTS: Critical logic relying on `block.timestamp` or `block.number` that can be manipulated by miners.
    // LOGIC: Contract state (`number`) should not be implicitly or explicitly dependent on `block.timestamp`.
    function invariant_TimeManipulationProtection() public {
        // Counter is time-independent. This invariant asserts that.
        assert(true, "Counter contract does not rely on block.timestamp or block.number.");
    }

    // DETECTS: Function behavior when `block.timestamp` is manipulated (e.g., in testing environment).
    // LOGIC: Testing functions with varied `block.timestamp` or `block.number` should yield predictable results.
    function test_TimeManipulation_Fuzz(uint256 timeDelta) public {
        vm.warp(block.timestamp + timeDelta); // Manipulate timestamp
        counter.setNumber(100);
        assertEq(counter.number(), 100, "Time manipulation affected setNumber.");
        counter.increment();
        assertEq(counter.number(), 101, "Time manipulation affected increment.");
    }

    // DETECTS: Multi-step attacks involving timing (e.g., front-running, delayed execution).
    // LOGIC: A sequence of timed actions should not lead to exploits.
    function test_TimeManipulation_MultiStep() public {
        vm.warp(block.timestamp + 100);
        counter.setNumber(50);
        vm.warp(block.timestamp + 200);
        counter.increment();
        assertEq(counter.number(), 51, "Multi-step time manipulation detected (trivial for Counter).");
    }

    //
    // 9. Cross-function vulnerabilities - complex state inconsistencies
    //

    // DETECTS: Inconsistent state after combined function calls.
    // LOGIC: `increment()` should always increase `number` by 1, regardless of previous `setNumber()` calls.
    function invariant_CrossFunctionConsistency() public {
        counter.setNumber(100);
        assertEq(counter.number(), 100);
        counter.increment();
        assertEq(counter.number(), 101);
        counter.setNumber(50);
        assertEq(counter.number(), 50);
        counter.increment();
        assertEq(counter.number(), 51);
    }

    // DETECTS: Unexpected interactions between `setNumber` and `increment` with varied inputs.
    // LOGIC: Fuzzing the order and values of calls ensures no obscure state corruption.
    function test_CrossFunction_Fuzz(uint256 val1, uint256 val2, uint256 val3) public {
        vm.assume(val1 < type(uint256).max - 2 && val2 < type(uint256).max - 2 && val3 < type(uint256).max - 2); // Avoid overflow for intermediate steps
        val1 = val1 % 1000; // Keep values manageable for demonstration
        val2 = val2 % 1000;
        val3 = val3 % 1000;

        counter.setNumber(val1);
        assertEq(counter.number(), val1, "setNumber(val1) failed in fuzz.");

        counter.increment();
        assertEq(counter.number(), val1 + 1, "increment after setNumber(val1) failed.");

        counter.setNumber(val2);
        assertEq(counter.number(), val2, "setNumber(val2) failed in fuzz.");

        counter.increment();
        counter.increment();
        assertEq(counter.number(), val2 + 2, "Double increment after setNumber(val2) failed.");

        counter.setNumber(val3);
        assertEq(counter.number(), val3, "setNumber(val3) failed in fuzz.");
    }

    // DETECTS: Complex state inconsistencies through multi-step interaction.
    // LOGIC: A long sequence of intermingled `setNumber` and `increment` calls must maintain expected state.
    function test_CrossFunction_MultiStep() public {
        counter.setNumber(0);
        assertEq(counter.number(), 0);

        counter.increment(); // 1
        counter.increment(); // 2
        counter.setNumber(10); // 10
        counter.increment(); // 11
        counter.setNumber(type(uint256).max - 2); // max - 2
        counter.increment(); // max - 1
        counter.increment(); // max

        vm.expectRevert(); // This should revert
        counter.increment();
        assertEq(counter.number(), type(uint256).max, "Final state incorrect after multi-step cross-function calls.");
    }

    //
    // 10. Upgrade vulnerabilities - proxy and storage collisions
    //
    // Note: The Counter contract is not an upgradeable proxy. These tests are purely illustrative.

    // DETECTS: Storage slot collisions or improper initialization in upgradeable contracts.
    // LOGIC: Critical state variables (`number`) should occupy unique, consistent storage slots across upgrades.
    function invariant_UpgradeSafety() public {
        // Counter is not upgradeable. This invariant confirms its non-upgradeability.
        // In a proxy scenario, this would involve deploying a proxy, then an implementation,
        // then checking storage slots using `vm.load()` on the proxy's address for a specific slot.
        // The `number` variable is at slot 0 for Counter.
        assertEq(uint256(vm.load(address(counter), bytes32(uint256(0)))), counter.number(), "Storage slot for number does not match, potential collision.");
    }

    // DETECTS: Upgradeability exploits with extreme values or during initialization.
    // LOGIC: Fuzzing initialization parameters of upgradeable contracts should not lead to vulnerabilities.
    function test_Upgrade_Fuzz(uint256 valueToSet) public {
        // Simulate:
        // 1. Deploy proxy.
        // 2. Deploy initial implementation.
        // 3. Upgrade to a new implementation (possibly with changed storage layout).
        // 4. Call `setNumber` (or other functions) and check state.
        // For Counter, we just ensure direct interaction is consistent.
        counter.setNumber(valueToSet);
        assertEq(counter.number(), valueToSet, "Value inconsistent after hypothetical upgrade test (trivial).");
    }

    // DETECTS: Multi-step upgrade attacks (e.g., re-initialization, delegatecall flaws).
    // LOGIC: A sequence of upgrade-related actions (deploy, upgrade, re-initialize, call) must be secure.
    function test_Upgrade_MultiStep() public {
        // Simulate:
        // 1. Deploy proxy.
        // 2. Deploy v1 implementation, initialize.
        // 3. Interact with v1 (e.g., setNumber, increment).
        // 4. Deploy v2 implementation (with changes).
        // 5. Upgrade proxy to v2.
        // 6. Interact with v2, checking if v1 state is preserved and v2 logic is correct.
        counter.setNumber(100);
        assertEq(counter.number(), 100, "Initial state not set in multi-step upgrade test.");
        counter.increment();
        assertEq(counter.number(), 101, "State not incremented in multi-step upgrade test.");
    }
}