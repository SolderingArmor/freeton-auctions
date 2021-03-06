pragma ton-solidity >=0.44.0;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;

//================================================================================
//
import "../interfaces/IAuctionManager.sol";
import "../contracts/AuctionDnsRecord.sol";

//================================================================================
//
contract AuctionManagerDnsRecord is IAuctionManager
{
    //========================================
    //
    function calculateAuctionInit(address sellerAddress, address buyerAddress, address assetAddress, AUCTION_TYPE auctionType, uint32 dtStart) public view override returns (address, TvmCell)
    {
        TvmCell stateInit = tvm.buildStateInit({
            contr: AuctionDnsRecord,
            varInit: {
                _sellerAddress: sellerAddress,
                _buyerAddress:  buyerAddress,
                _assetAddress:  assetAddress,
                _auctionType:   auctionType,
                _bidCode:      _bidCode,
                _dtStart:       dtStart
            },
            code: _auctionCode
        });

        return (address(tvm.hash(stateInit)), stateInit);
    }
    
    //========================================
    //
    constructor(address ownerAddress) public
    { 
        tvm.accept();
        _ownerAddress = ownerAddress;
    }

    //========================================
    //
    function createAuction(address sellerAddress, address buyerAddress, address assetAddress, AUCTION_TYPE auctionType, uint32 dtStart,
                           uint128 feeValue, uint128 minBid, uint128 minPriceStep, uint128 buyNowPrice, uint32 dtEnd, uint32 dtRevealEnd, uint32 dutchCycle) external view override reserve returns (address)
    {
        (address auctionAddress, TvmCell stateInit) = calculateAuctionInit(sellerAddress, buyerAddress, assetAddress, auctionType, dtStart);
        new AuctionDnsRecord{value: 0, flag: 128, wid: address(this).wid, stateInit: stateInit}(_ownerAddress, 500, feeValue, minBid, minPriceStep, buyNowPrice, dtEnd, dtRevealEnd, dutchCycle);

        return auctionAddress;
    }
    
    //========================================
    //    
}

//================================================================================
//