// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SimpleNFTTracker} from "../src/NFTtracker.sol";

contract NFTtrackerTest is Test {
    SimpleNFTTracker public nftTracker;

    // Designated address for the contract owner in tests
    address public OWNER_DEPLOYER;
    // General purpose user addresses for testing various roles
    address public USER1 = vm.addr(1);
    address public USER2 = vm.addr(2);
    address public USER3 = vm.addr(3);

    /// @notice Sets up the testing environment before each test function runs.
    function setUp() public {
        // Assign a specific address to be the contract deployer and owner
        OWNER_DEPLOYER = vm.addr(999);

        // Deploy the SimpleNFTTracker contract using `OWNER_DEPLOYER` as msg.sender
        vm.startPrank(OWNER_DEPLOYER);
        nftTracker = new SimpleNFTTracker();
        vm.stopPrank();

        // Assert that the contract's owner state variable is correctly set
        require(nftTracker.owner() == OWNER_DEPLOYER, "Test setup error: contract owner not set correctly");
    }

    // --- Access Control Tests ---

    /// @notice Tests that only the contract owner can successfully call the `mint` function.
    function test_AC_OnlyOwnerCanMint() public {
        vm.prank(OWNER_DEPLOYER); // Prank as the owner
        uint256 tokenId = nftTracker.mint(USER1); // Owner mints a token to USER1

        require(tokenId == 1, "Expected first token ID to be 1");
        require(nftTracker.getTokenOwner(tokenId) == USER1, "Token should be owned by USER1 after mint");
    }

    /// @notice Tests that a non-owner attempting to call `mint` reverts with the expected error.
    function test_AC_RevertsIfNonOwnerMints() public {
        vm.prank(USER1); // Prank as a non-owner (USER1)
        vm.expectRevert("SNT: Only owner can call this");
        nftTracker.mint(USER2); // USER1 attempts to mint a token
    }

    /// @notice Tests that only the current owner of a specific token can transfer it.
    function test_AC_OnlyTokenOwnerCanTransfer() public {
        // 1. Owner mints a token to USER1
        vm.prank(OWNER_DEPLOYER);
        uint256 tokenId = nftTracker.mint(USER1);

        // 2. USER1 (the current token owner) transfers their token to USER2
        vm.prank(USER1);
        vm.expectEmit(true, true, true, true); // (from, to, tokenId, msg.sender)
        emit SimpleNFTTracker.TokenTransferred(USER1, USER2, tokenId);
        nftTracker.transfer(USER2, tokenId);

        // 3. Verify that the ownership has indeed changed to USER2
        require(nftTracker.getTokenOwner(tokenId) == USER2, "Token ownership should have transferred to USER2");
    }

    /// @notice Tests that a non-owner of a specific token attempting to transfer it reverts.
    function test_AC_RevertsIfNonTokenOwnerTransfers() public {
        // 1. Owner mints a token to USER1
        vm.prank(OWNER_DEPLOYER);
        uint256 tokenId = nftTracker.mint(USER1);

        // 2. USER2 (who does not own `tokenId`) tries to transfer it
        vm.prank(USER2);
        vm.expectRevert("SNT: Caller is not the owner");
        nftTracker.transfer(USER3, tokenId);
    }

    // --- Core Functionality / State Consistency / Edge Cases Tests ---

    /// @notice Tests that `mint` correctly increments token IDs and assigns ownership.
    function test_Core_Mint_IncrementsTokenIdAndAssignsOwnership() public {
        vm.prank(OWNER_DEPLOYER);

        // Mint the first token
        uint256 tokenId1 = nftTracker.mint(USER1);
        require(tokenId1 == 1, "First token ID should be 1");
        require(nftTracker.getTokenOwner(tokenId1) == USER1, "Token 1 not owned by USER1");

        // Mint the second token
        uint256 tokenId2 = nftTracker.mint(USER2);
        require(tokenId2 == 2, "Second token ID should be 2");
        require(nftTracker.getTokenOwner(tokenId2) == USER2, "Token 2 not owned by USER2");
    }

    /// @notice Tests that `mint` emits the `TokenMinted` event with correct parameters.
    function test_Core_Mint_EmitsTokenMintedEvent() public {
        vm.prank(OWNER_DEPLOYER);
        vm.expectEmit(true, true, false, true); // (indexed `to`, indexed `tokenId`, non-indexed `_`, msg.sender)
        emit SimpleNFTTracker.TokenMinted(USER1, 1);
        nftTracker.mint(USER1);
    }

    /// @notice Tests that `mint` reverts if the recipient address is `address(0)`.
    function test_Core_Mint_RevertsOnZeroAddressRecipient() public {
        vm.prank(OWNER_DEPLOYER);
        vm.expectRevert("SNT: Recipient is zero address");
        nftTracker.mint(address(0));
    }

    /// @notice Tests that `transfer` correctly updates ownership and emits the `TokenTransferred` event.
    function test_Core_Transfer_UpdatesOwnershipAndEmitsEvent() public {
        // 1. Owner mints a token to USER1
        vm.prank(OWNER_DEPLOYER);
        uint256 tokenId = nftTracker.mint(USER1);

        // 2. USER1 (current owner) transfers the token to USER2
        vm.prank(USER1);
        vm.expectEmit(true, true, true, true); // (from, to, tokenId, msg.sender)
        emit SimpleNFTTracker.TokenTransferred(USER1, USER2, tokenId);
        nftTracker.transfer(USER2, tokenId);

        // 3. Verify the new owner is USER2
        require(nftTracker.getTokenOwner(tokenId) == USER2, "Token ownership not updated");
        // 4. Verify that the previous owner (USER1) can no longer transfer the token
        vm.prank(USER1);
        vm.expectRevert("SNT: Caller is not the owner");
        nftTracker.transfer(USER3, tokenId);
    }

    /// @notice Tests that `transfer` reverts if the specified `tokenId` does not exist.
    function test_Core_Transfer_RevertsOnNonExistentToken() public {
        // Any user trying to transfer a token that was never minted
        vm.prank(USER1);
        vm.expectRevert("SNT: Token does not exist");
        nftTracker.transfer(USER2, 999); // Token ID 999 has not been minted
    }

    /// @notice Tests that `transfer` reverts if the recipient address is `address(0)`.
    function test_Core_Transfer_RevertsOnZeroAddressRecipient() public {
        // 1. Owner mints a token to USER1
        vm.prank(OWNER_DEPLOYER);
        uint256 tokenId = nftTracker.mint(USER1);

        // 2. USER1 tries to transfer to `address(0)`
        vm.prank(USER1);
        vm.expectRevert("SNT: Recipient is zero address");
        nftTracker.transfer(address(0), tokenId);
    }

    /// @notice Tests that `getTokenOwner` reverts when queried for a non-existent token.
    function test_Core_GetTokenOwner_RevertsOnNonExistentToken() public {
        vm.expectRevert("SNT: Token does not exist");
        nftTracker.getTokenOwner(999); // Token ID 999 has not been minted
    }

    // --- Fuzz Test ---

    /// @notice Fuzz test to verify `transfer` ownership conditions and state updates under various sender/recipient scenarios.
    /// @param _randomSender A fuzzed address representing `msg.sender` for the `transfer` call.
    /// @param _randomRecipient A fuzzed address representing the `to` parameter for the `transfer` call.
    function testFuzz_TransferOwnershipConditions(address _randomSender, address _randomRecipient) public {
        // --- Assumptions for practical fuzzing inputs ---
        vm.assume(_randomRecipient != address(0)); // Recipient should not be the zero address
        vm.assume(_randomSender != address(0));    // Sender should not be the zero address (contract logic handles this too, but for clearer fuzzing intent)

        // --- Setup for each fuzz iteration ---
        // Mint a token to a known address (USER1) for consistent testing across fuzz runs.
        // This ensures a valid token exists with a predictable owner for verification.
        vm.startPrank(OWNER_DEPLOYER);
        uint256 tokenId = nftTracker.mint(USER1);
        vm.stopPrank();

        // Retrieve the current owner of the token (should be USER1 from setup)
        address currentOwner = nftTracker.getTokenOwner(tokenId);
        require(currentOwner == USER1, "Test setup error: minted token not owned by USER1");

        // --- Execute transfer attempt with fuzzed parameters ---
        vm.prank(_randomSender); // Set the fuzzed sender as `msg.sender`

        if (_randomSender == currentOwner) {
            // Case 1: The fuzzed sender IS the actual owner of the token.
            // Expected outcome: Transfer should succeed, and an event should be emitted.
            vm.expectEmit(true, true, true, true);
            emit SimpleNFTTracker.TokenTransferred(currentOwner, _randomRecipient, tokenId);
            nftTracker.transfer(_randomRecipient, tokenId);
            // Verify that the token's ownership has indeed changed to the fuzzed recipient
            require(nftTracker.getTokenOwner(tokenId) == _randomRecipient, "Ownership should change to new recipient on valid transfer");
        } else {
            // Case 2: The fuzzed sender is NOT the actual owner of the token.
            // Expected outcome: Transfer should revert with an access control error.
            vm.expectRevert("SNT: Caller is not the owner");
            nftTracker.transfer(_randomRecipient, tokenId);
            // Verify that ownership *did not* change after the failed transfer attempt
            require(nftTracker.getTokenOwner(tokenId) == currentOwner, "Ownership should NOT change if non-owner tries to transfer");
        }
    }
}