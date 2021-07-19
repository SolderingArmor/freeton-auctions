pragma ton-solidity >=0.44.0;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;

//================================================================================
//
import "../interfaces/IOwnable.sol";
import "../interfaces/IAuction.sol";

//================================================================================
//
abstract contract IAuctionManager is IOwnable
{
    //========================================
    // Variables
    TvmCell static _bidCode;      //
    TvmCell static _auctionCode;  //

    //========================================
    //
    function getHashFromPrice(uint128 price, uint256 salt) external pure returns (uint256)
    {
        TvmBuilder builder;
        builder.store(price);
        builder.store(salt);
        TvmCell cell = builder.toCell();
        return tvm.hash(cell);
    }
    
    //========================================
    //
    function calculateAuctionInit(address sellerAddress, address buyerAddress, address assetAddress, AUCTION_TYPE auctionType, uint32 dtStart) external view virtual returns (address, TvmCell);

    function createAuction(address sellerAddress, address buyerAddress, address assetAddress, AUCTION_TYPE auctionType, uint32 dtStart,
                           uint128 feeValue, uint128 minBid, uint128 minPriceStep, uint128 buyNowPrice, uint32 dtEnd, uint32 dtRevealEnd, uint32 dutchCycle) external view virtual returns (address);
}

//================================================================================
//