pragma solidity ^0.8.0;
contract AuctionFixed 
{
    event BidEvent(address from);
    function bid() public
    {
        emitBidEvent(msg.sender);
    }

    function emitBidEvent(address from) internal
    {
        emit BidEvent(from);
    }
}