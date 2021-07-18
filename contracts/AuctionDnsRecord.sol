pragma ton-solidity >=0.44.0;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;

//================================================================================
//
import "../interfaces/IDnsRecord.sol";
import "../interfaces/IAuction.sol";

//================================================================================
//
contract AuctionDnsRecord is IAuction
{
    //========================================
    //
    /*constructor() public
    {
        _init();
    }*/
    constructor(address escrowAddress,
                uint16  escrowPercent,
                uint128 feeValue,
                uint128 minBid,
                uint128 minPriceStep,
                uint128 buyNowPrice,
                uint32  dtEnd,
                uint32  dtRevealEnd,
                uint32  dutchCycle) public
    {
        _init(escrowAddress,
              escrowPercent,
              feeValue,
              minBid,
              minPriceStep,
              buyNowPrice,
              dtEnd,
              dtRevealEnd,
              dutchCycle);
    }

    //========================================
    //
    function deliverAsset(address receiver) internal override
    {
        if(_assetDelivered) { return; }
        IDnsRecord(_assetAddress).changeOwner{value: 0, bounce: true, flag: 128}(receiver);
    }
    
    //========================================
    //
    function checkAssetDelivered() internal override
    {
        _reserve();
        if(_assetDelivered)
        {
            return;
        }

        IDnsRecord(_assetAddress).callWhois{value: 0, callback: callbackOnCheckAssetDelivered, flag: 128}();
    }
    
    //========================================
    //
    function callbackOnCheckAssetDelivered(DnsWhois whois) public onlyAsset
    {
        _reserve();
        address desiredOwner = (_currentBuyer      == addressZero ? _sellerAddress : _currentBuyer);
        _assetDelivered      = (whois.ownerAddress == desiredOwner);
        
        if(_assetDelivered)
        {
             _sellerAddress.transfer(0, true, 128);
        }
        else
        {
            deliverAsset(desiredOwner);
        }
    }

    //========================================
    //
    function receiveAsset() public override onlySeller
    {
        _reserve();
        IDnsRecord(_assetAddress).callWhois{value: 0, callback: callbackOnReceiveAsset, flag: 128}();
    }
    
    //========================================
    //
    function callbackOnReceiveAsset(DnsWhois whois) public onlyAsset
    {
        _reserve();
        _assetReceived  = (whois.ownerAddress == address(this));
        _auctionStarted = (whois.ownerAddress == address(this));
        _sellerAddress.transfer(0, true, 128);
    }
}

//================================================================================
//
