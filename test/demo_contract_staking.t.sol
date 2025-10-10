// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract DecentralizedMarketplace {
    
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        address paymentToken;
        bool active;
        uint256 listedAt;
    }
    
    struct Offer {
        address buyer;
        uint256 amount;
        uint256 expiresAt;
        bool active;
    }
    
    struct Auction {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 startPrice;
        uint256 highestBid;
        address highestBidder;
        uint256 endTime;
        address paymentToken;
        bool active;
    }
    
    address public owner;
    uint256 public platformFee;
    uint256 public listingCounter;
    uint256 public auctionCounter;
    
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => mapping(address => Offer)) public offers;
    mapping(uint256 => Auction) public auctions;
    mapping(address => uint256) public escrowBalance;
    mapping(address => bool) public approvedPaymentTokens;
    
    event Listed(uint256 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price);
    event Sale(uint256 indexed listingId, address indexed buyer, uint256 price);
    event OfferMade(uint256 indexed listingId, address indexed buyer, uint256 amount);
    event OfferAccepted(uint256 indexed listingId, address indexed buyer, uint256 amount);
    event AuctionCreated(uint256 indexed auctionId, address indexed seller, uint256 startPrice, uint256 endTime);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 amount);
    event ListingCancelled(uint256 indexed listingId);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }
    
    constructor(uint256 _platformFee) {
        owner = msg.sender;
        platformFee = _platformFee;
    }
    
    function approvePaymentToken(address token) external onlyOwner {
        approvedPaymentTokens[token] = true;
    }
    
    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        address paymentToken
    ) external returns (uint256) {
        require(price > 0, "Price must be greater than 0");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(approvedPaymentTokens[paymentToken], "Payment token not approved");
        
        listingCounter++;
        
        listings[listingCounter] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            paymentToken: paymentToken,
            active: true,
            listedAt: block.timestamp
        });
        
        emit Listed(listingCounter, msg.sender, nftContract, tokenId, price);
        return listingCounter;
    }
    
    function buyNFT(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(msg.sender != listing.seller, "Cannot buy own listing");
        
        uint256 fee = (listing.price * platformFee) / 10000;
        uint256 sellerAmount = listing.price - fee;
        
        IERC20 token = IERC20(listing.paymentToken);
        require(token.transferFrom(msg.sender, address(this), listing.price), "Payment failed");
        require(token.transfer(listing.seller, sellerAmount), "Seller payment failed");
        require(token.transfer(owner, fee), "Fee payment failed");
        
        IERC721(listing.nftContract).transferFrom(listing.seller, msg.sender, listing.tokenId);
        
        listing.active = false;
        
        emit Sale(listingId, msg.sender, listing.price);
    }
    
    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(msg.sender == listing.seller, "Not seller");
        
        listing.active = false;
        emit ListingCancelled(listingId);
    }
    
    function makeOffer(uint256 listingId, uint256 amount, uint256 duration) external {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(amount > 0, "Invalid amount");
        require(msg.sender != listing.seller, "Cannot offer on own listing");
        
        IERC20 token = IERC20(listing.paymentToken);
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        escrowBalance[msg.sender] += amount;
        
        offers[listingId][msg.sender] = Offer({
            buyer: msg.sender,
            amount: amount,
            expiresAt: block.timestamp + duration,
            active: true
        });
        
        emit OfferMade(listingId, msg.sender, amount);
    }
    
    function acceptOffer(uint256 listingId, address buyer) external {
        Listing storage listing = listings[listingId];
        Offer storage offer = offers[listingId][buyer];
        
        require(listing.active, "Listing not active");
        require(offer.active, "Offer not active");
        require(block.timestamp <= offer.expiresAt, "Offer expired");
        
        uint256 fee = (offer.amount * platformFee) / 10000;
        uint256 sellerAmount = offer.amount - fee;
        
        escrowBalance[buyer] -= offer.amount;
        
        IERC20 token = IERC20(listing.paymentToken);
        require(token.transfer(listing.seller, sellerAmount), "Seller payment failed");
        require(token.transfer(owner, fee), "Fee payment failed");
        
        IERC721(listing.nftContract).transferFrom(listing.seller, buyer, listing.tokenId);
        
        listing.active = false;
        offer.active = false;
        
        emit OfferAccepted(listingId, buyer, offer.amount);
    }
    
    function withdrawOffer(uint256 listingId) external {
        Offer storage offer = offers[listingId][msg.sender];
        require(offer.active, "No active offer");
        
        uint256 amount = offer.amount;
        offer.active = false;
        escrowBalance[msg.sender] -= amount;
        
        IERC20 token = IERC20(listings[listingId].paymentToken);
        require(token.transfer(msg.sender, amount), "Withdrawal failed");
    }
    
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 duration,
        address paymentToken
    ) external returns (uint256) {
        require(startPrice > 0, "Invalid start price");
        require(duration > 0, "Invalid duration");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(approvedPaymentTokens[paymentToken], "Payment token not approved");
        
        auctionCounter++;
        
        auctions[auctionCounter] = Auction({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            startPrice: startPrice,
            highestBid: 0,
            highestBidder: address(0),
            endTime: block.timestamp + duration,
            paymentToken: paymentToken,
            active: true
        });
        
        emit AuctionCreated(auctionCounter, msg.sender, startPrice, block.timestamp + duration);
        return auctionCounter;
    }
    
    function placeBid(uint256 auctionId, uint256 amount) external {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(amount > auction.highestBid, "Bid too low");
        require(amount >= auction.startPrice, "Below start price");
        
        IERC20 token = IERC20(auction.paymentToken);
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        if (auction.highestBidder != address(0)) {
            require(token.transfer(auction.highestBidder, auction.highestBid), "Refund failed");
        }
        
        auction.highestBid = amount;
        auction.highestBidder = msg.sender;
        
        emit BidPlaced(auctionId, msg.sender, amount);
    }
    
    function endAuction(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(block.timestamp >= auction.endTime, "Auction not ended");
        
        auction.active = false;
        
        if (auction.highestBidder != address(0)) {
            uint256 fee = (auction.highestBid * platformFee) / 10000;
            uint256 sellerAmount = auction.highestBid - fee;
            
            IERC20 token = IERC20(auction.paymentToken);
            require(token.transfer(auction.seller, sellerAmount), "Seller payment failed");
            require(token.transfer(owner, fee), "Fee payment failed");
            
            IERC721(auction.nftContract).transferFrom(
                auction.seller,
                auction.highestBidder,
                auction.tokenId
            );
            
            emit AuctionEnded(auctionId, auction.highestBidder, auction.highestBid);
        } else {
            emit AuctionEnded(auctionId, address(0), 0);
        }
    }
    
    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        platformFee = _platformFee;
    }
    
    function getListingDetails(uint256 listingId) external view returns (
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool active
    ) {
        Listing memory listing = listings[listingId];
        return (
            listing.seller,
            listing.nftContract,
            listing.tokenId,
            listing.price,
            listing.active
        );
    }
    
    function getAuctionDetails(uint256 auctionId) external view returns (
        address seller,
        uint256 highestBid,
        address highestBidder,
        uint256 endTime,
        bool active
    ) {
        Auction memory auction = auctions[auctionId];
        return (
            auction.seller,
            auction.highestBid,
            auction.highestBidder,
            auction.endTime,
            auction.active
        );
    }
    
    function emergencyWithdraw(address token) external onlyOwner {
        IERC20(token).transfer(owner, IERC20(token).balanceOf(address(this)));
    }
    
    function updateOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}