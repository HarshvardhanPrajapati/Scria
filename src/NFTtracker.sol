// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SimpleNFTTracker
 * @notice A basic contract to demonstrate a non-fungible token (NFT) ownership tracker.
 * This is NOT a full ERC-721 implementation and is designed for simplicity and conciseness.
 */
contract SimpleNFTTracker {
    // --- State Variables ---

    // The address authorized to mint new tokens.
    address public owner;
    // The next available token ID to be minted. Starts at 1.
    uint256 private _nextTokenId = 1;

    // Mapping from token ID to owner address.
    mapping(uint256 => address) private _owners;

    // --- Events ---

    // Emitted when a new token is created.
    event TokenMinted(address indexed to, uint256 indexed tokenId);
    // Emitted when a token's ownership changes.
    event TokenTransferred(address indexed from, address indexed to, uint256 indexed tokenId);

    // --- Constructor ---

    constructor() {
        owner = msg.sender;
    }

    // --- Modifiers ---

    // Restricts access to the contract owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "SNT: Only owner can call this");
        _;
    }

    // --- Public Functions (View) ---

    /**
     * @notice Returns the address of the owner of a specific token.
     * @param tokenId The ID of the token to query.
     */
    function getTokenOwner(uint256 tokenId) public view returns (address) {
        address currentOwner = _owners[tokenId];
        require(currentOwner != address(0), "SNT: Token does not exist");
        return currentOwner;
    }

    // --- Public Functions (Write) ---

    /**
     * @notice Mints a new token and assigns it to the recipient.
     * @param recipient The address to receive the newly minted token.
     * @return The ID of the newly minted token.
     */
    function mint(address recipient) public onlyOwner returns (uint256) {
        require(recipient != address(0), "SNT: Recipient is zero address");

        uint256 newTokenId = _nextTokenId;
        _owners[newTokenId] = recipient;
        _nextTokenId++;

        emit TokenMinted(recipient, newTokenId);
        return newTokenId;
    }

    /**
     * @notice Transfers ownership of a token from the caller to a new address.
     * @param to The address to receive the token.
     * @param tokenId The ID of the token to transfer.
     */
    function transfer(address to, uint256 tokenId) public {
        address currentOwner = _owners[tokenId];

        require(currentOwner == msg.sender, "SNT: Caller is not the owner");
        require(to != address(0), "SNT: Recipient is zero address");

        // Perform the transfer
        _owners[tokenId] = to;

        emit TokenTransferred(currentOwner, to, tokenId);
    }
}
