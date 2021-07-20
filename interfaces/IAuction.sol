pragma ton-solidity >=0.44.0;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;

//================================================================================
//
import "../contracts/AuctionBid.sol";

//================================================================================
//
enum AUCTION_TYPE
{
    ENGLISH_FORWARD, //
    ENGLISH_BLIND,   //
    DUTCH_FORWARD,   //
    PUBLIC_BUY,      //
    PRIVATE_BUY,     //
    NUM              //
}

//================================================================================
// TODO: update started and succeeded and etc
abstract contract IAuction
{
    //========================================
    // Constants
    address constant addressZero = address.makeAddrStd(0, 0);

    //========================================
    // Error codes
    uint constant ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER = 100;
    uint constant ERROR_MESSAGE_SENDER_IS_NOT_MY_BID   = 101;
    uint constant ERROR_AUCTION_NOT_RUNNING            = 200;
    uint constant ERROR_AUCTION_ENDED                  = 201;
    uint constant ERROR_ASSET_NOT_TRANSFERRED          = 202;
    uint constant ERROR_AUCTION_IN_PROCESS             = 203;
    uint constant ERROR_PRICE_REVEAL_IN_PROCESS        = 204;
    uint constant ERROR_NOT_ENOUGH_MONEY               = 205;
    uint constant ERROR_DO_NOT_BEAT_YOURSELF           = 206;
    uint constant ERROR_MESSAGE_SENDER_IS_NOT_SELLER   = 207;
    uint constant ERROR_MESSAGE_SENDER_IS_NOT_ASSET    = 208;
    uint constant ERROR_INVALID_AUCTION_TYPE           = 209;
    uint constant ERROR_INVALID_BUYER_ADDRESS          = 210;
    uint constant ERROR_INVALID_START_DATE             = 211;
    uint constant ERROR_INVALID_END_DATE               = 212;

    //========================================
    // Variables
    address             _escrowAddress; // escrow multisig for collecting fees;
    uint16              _escrowPercent; // times 100; 1% = 100, 10% = 1000;
    address      static _sellerAddress; // seller is the real asset owner;
    address      static _buyerAddress;  // buyer is specified only when "_type" is AUCTION_TYPE.PRIVATE_BUY, otherwise 0:0000000000000000000000000000000000000000000000000000000000000000;
    address      static _assetAddress;  // asset contract address;
    AUCTION_TYPE static _auctionType;   //
    TvmCell      static _bidCode;       //
    uint128             _feeValue;      //
    uint128             _minBid;        // for English it is minimum price, for Dutch it is maximum price;
    uint128             _minPriceStep;  //
    uint128             _buyNowPrice;   //
    uint32       static _dtStart;       //
    uint32              _dtEnd;         //
    uint32              _dtRevealEnd;   //
    uint32              _dutchCycle;    // Period of time for Dutch auctions when the price decresaes by _minPriceStep value;

    bool         _assetReceived;        //
    bool         _auctionStarted;       //
    bool         _auctionSucceeded;     //
    bool         _moneySentOut;         //
    bool         _assetDelivered;       //

    address      _currentBuyer;         //
    uint128      _currentBuyPrice;      //
    uint32       _currentBuyDT;         //
    uint128      _currentBlindBets;     //

    //========================================
    // Modifiers
    function _reserve() internal inline view {    tvm.rawReserve(gasToValue(10000, address(this).wid), 0);    }
    modifier  onlySeller {    require(_sellerAddress != addressZero && _sellerAddress == msg.sender, ERROR_MESSAGE_SENDER_IS_NOT_SELLER);    _; }
    modifier  onlyAsset  {    require(_assetAddress  != addressZero && _assetAddress  == msg.sender, ERROR_MESSAGE_SENDER_IS_NOT_ASSET );    _; }
    modifier  reserve    {   _reserve();    _;    }

    //========================================
    //
    function calculateBidInit(address bidderAddress) public view returns (address, TvmCell)
    {
        TvmCell stateInit = tvm.buildStateInit({
            contr: AuctionBid,
            varInit: {
                _auctionAddress: address(this),
                _bidderAddress: bidderAddress
            },
            code: _bidCode
        });

        return (address(tvm.hash(stateInit)), stateInit);
    }

    //========================================
    //
    function getInfo() external view returns(address      escrowAddress,
                                             uint16       escrowPercent,
                                             address      sellerAddress,
                                             address      buyerAddress,
                                             address      assetAddress,
                                             AUCTION_TYPE auctionType,
                                             uint128      minBid,
                                             uint128      minPriceStep,
                                             uint128      buyNowPrice,
                                             uint32       dtStart,
                                             uint32       dtEnd,
                                             uint32       dtRevealEnd,
                                             uint32       dutchCycle,
                                             bool         assetReceived,
                                             bool         auctionStarted,
                                             bool         auctionSucceeded,
                                             bool         moneySentOut,
                                             bool         assetDelivered,
                                             address      currentBuyer,
                                             uint128      currentBuyPrice,
                                             uint32       currentBuyDT,
                                             uint128      currentBlindBets)
    {
        return(_escrowAddress,
               _escrowPercent,
               _sellerAddress,
               _buyerAddress,
               _assetAddress,
               _auctionType,
               _minBid,
               _minPriceStep,
               _buyNowPrice,
               _dtStart,
               _dtEnd,
               _dtRevealEnd,
               _dutchCycle,
               _assetReceived,
               _auctionStarted,
               _auctionSucceeded,
               _moneySentOut,
               _assetDelivered,
               _currentBuyer,
               _currentBuyPrice,
               _currentBuyDT,
               _currentBlindBets);
    }

    //========================================
    //
    function _init(address escrowAddress,
                   uint16  escrowPercent,
                   uint128 feeValue,
                   uint128 minBid,
                   uint128 minPriceStep,
                   uint128 buyNowPrice,
                   uint32  dtEnd,
                   uint32  dtRevealEnd,
                   uint32  dutchCycle) internal inline
    {
        //require(_dtStart >= now,            ERROR_INVALID_START_DATE);
        require(_dtStart < dtEnd,            ERROR_INVALID_END_DATE);
        require(_dtEnd <= now + 60*60*24*60, ERROR_INVALID_END_DATE); // Maximum auction period is 60 days
        if(_auctionType == AUCTION_TYPE.ENGLISH_BLIND)
        {
            require(dtEnd < dtRevealEnd, ERROR_INVALID_END_DATE);
        }
        
        _escrowAddress        = escrowAddress; //
        _escrowPercent        = escrowPercent; //
        _feeValue             = feeValue;      //
        _minBid               = minBid;        //
        _minPriceStep         = minPriceStep;  //
        _buyNowPrice          = buyNowPrice;   //
        _dtEnd                = dtEnd;         //
        _dtRevealEnd          = dtRevealEnd;   //
        _dutchCycle           = dutchCycle;    //
        _assetReceived        = false;
        _auctionStarted       = false; // Start only after we are sure that asset is transfered to auction contract;
        _auctionSucceeded     = false; // Finish after time is out or when the public/private buy is done;
        _moneySentOut         = false; // Called when finalize is first called;
        _assetDelivered       = false;
        _currentBuyer         = addressZero;
        _currentBuyPrice      = 0;
        _currentBuyDT         = 0;
    }

    //========================================
    // Cancel auction
    function cancelAuction() external onlySeller
    {
        require(_currentBuyer == addressZero && _currentBlindBets == 0, ERROR_AUCTION_IN_PROCESS);

        _reserve(); // reserve minimum balance;
        _auctionSucceeded     = true;

        // return the change
        msg.sender.transfer(0, true, 128);
    }

    //========================================
    //
    function getDesiredPrice() public view returns (uint128)
    {        
        uint128 desiredPrice = 0;
        if(_auctionType == AUCTION_TYPE.ENGLISH_FORWARD)
        {
            if(_currentBuyPrice == 0)
            {
                desiredPrice = _minBid;
            }
            else
            {
                if(_buyNowPrice > 0)
                {
                    desiredPrice = math.min(_currentBuyPrice + _minPriceStep, _buyNowPrice);
                }
                else
                {
                    desiredPrice = _currentBuyPrice + _minPriceStep;
                }
            }
        }
        else if(_auctionType == AUCTION_TYPE.ENGLISH_BLIND)  {    desiredPrice = 0;               } // We don't know the price when the auction is BLIND;
        else if(_auctionType == AUCTION_TYPE.PUBLIC_BUY)     {    desiredPrice = _buyNowPrice;    }
        else if(_auctionType == AUCTION_TYPE.PRIVATE_BUY)    {    desiredPrice = _buyNowPrice;    }
        else if(_auctionType == AUCTION_TYPE.DUTCH_FORWARD)
        {
            uint32 timePassed = now - _dtStart;
            (uint32 fullCyclesNum, ) = math.divmod(timePassed, _dutchCycle);
            uint128 amountToSubtract = fullCyclesNum * _minPriceStep;
            if(amountToSubtract >= _minBid)
            {
                desiredPrice = _buyNowPrice;
            }
            else
            {
                desiredPrice = math.max(_minBid - amountToSubtract, _buyNowPrice);
            }
        }

        return desiredPrice;
    }

    //========================================
    // Place a new blind bid
    function bidBlind(uint256 priceHash) external
    {
        require(_auctionType == AUCTION_TYPE.ENGLISH_BLIND, ERROR_INVALID_AUCTION_TYPE);
        require(msg.value >  _feeValue,                     ERROR_NOT_ENOUGH_MONEY    );
        require(now >= _dtStart && now <= _dtEnd,           ERROR_AUCTION_NOT_RUNNING );
        require( _auctionStarted,                           ERROR_AUCTION_NOT_RUNNING );
        require(!_auctionSucceeded,                         ERROR_AUCTION_ENDED       );
        
        (address bidAddress, TvmCell bidInit) = calculateBidInit(msg.sender);
        
        new AuctionBid{value: msg.value / 2, flag: 0, bounce: false, wid: address(this).wid, stateInit: bidInit}(_feeValue);
        AuctionBid(bidAddress).setPriceHash{value: 0, flag: 128}(priceHash);

        _currentBlindBets += 1;
    }

    //========================================
    // 
    function revealBidBlind(uint128 price, uint256 salt) external view
    {
        require(now >= _dtEnd && now <= _dtRevealEnd, ERROR_AUCTION_NOT_RUNNING);
        require(msg.value > price,                    ERROR_NOT_ENOUGH_MONEY   );
        (address bidAddress, ) = calculateBidInit(msg.sender);
        _reserve();

        // We don't want to mess with current revealed bid
        if(_currentBuyPrice > 0)
        {
            tvm.rawReserve(_currentBuyPrice, 0);
        }

        AuctionBid(bidAddress).revealPriceHash{value: 0, flag: 128, callback: callbackRevealBidBlind}(price, salt);
    }

    function callbackRevealBidBlind(uint128 revealedPrice, uint256 revealedSalt, uint256 revealedHash, uint256 actualHash, address bidderAddress) public
    {
        (address bidAddress, ) = calculateBidInit(bidderAddress);
        require(msg.sender == bidAddress, ERROR_MESSAGE_SENDER_IS_NOT_MY_BID);
        _reserve();

        // Shut down the warning
        revealedSalt = 0;

        //
        if(revealedHash != actualHash)
        {
            tvm.rawReserve(_currentBuyPrice, 0);
            bidderAddress.transfer(0, true, 128);
            return;
        }

        if(revealedPrice <= _currentBuyPrice)
        {
            tvm.rawReserve(_currentBuyPrice, 0);
            bidderAddress.transfer(0, true, 128);
            return;
        }
        
        // return TONs to previous buyer (if there is any);
        if(_currentBuyer != addressZero)
        {
            _currentBuyer.transfer(_currentBuyPrice, true, 0); 
        }

        // Update current buyer
        _currentBuyer    = bidderAddress;
        _currentBuyPrice = revealedPrice;
        _currentBuyDT    = now;

        tvm.rawReserve(_currentBuyPrice, 0);
        _currentBuyer.transfer(0, true, 128);
    }
    
    //========================================
    // Place a new bid
    function bid() external
    {
        require(_auctionType <  AUCTION_TYPE.NUM,           ERROR_INVALID_AUCTION_TYPE );
        require(_auctionType != AUCTION_TYPE.ENGLISH_BLIND, ERROR_INVALID_AUCTION_TYPE );
        if(_auctionType == AUCTION_TYPE.PRIVATE_BUY)
        {
            require(msg.sender == _buyerAddress && _buyerAddress != addressZero, ERROR_INVALID_BUYER_ADDRESS);
        }

        uint128 desiredPrice = getDesiredPrice();

        require(now >= _dtStart && now <= _dtEnd,       ERROR_AUCTION_NOT_RUNNING  );
        require( _auctionStarted,                       ERROR_AUCTION_NOT_RUNNING  );
        require(!_auctionSucceeded,                     ERROR_AUCTION_ENDED        );
        require(msg.sender != _currentBuyer,            ERROR_DO_NOT_BEAT_YOURSELF );
        require(msg.value  >= desiredPrice + _feeValue, ERROR_NOT_ENOUGH_MONEY     );

        _reserve(); // reserve minimum balance;

        if(_auctionType == AUCTION_TYPE.ENGLISH_FORWARD)
        {
            // If there is no BUY NOW price or the bet is lower
            if(_buyNowPrice == 0 || msg.value - _feeValue < _buyNowPrice)
            {
                tvm.rawReserve(msg.value - _feeValue, 0); // reserve new buyer's amount; previous buyer pays the fees;
            }
            else // the bet is above BUY NOW price
            {
                tvm.rawReserve(_buyNowPrice, 0); // reserve buy price, we don't want the change;
                _auctionSucceeded = true;
            }

            // return TONs to previous buyer;
            if(_currentBuyer != addressZero)
            {
                _currentBuyer.transfer(_currentBuyPrice, true, 0); 
            }

            // Update current buyer
            _currentBuyer    = msg.sender;
            _currentBuyPrice = msg.value - _feeValue;
            _currentBuyDT    = now;
        }
        else if(_auctionType == AUCTION_TYPE.PUBLIC_BUY || _auctionType == AUCTION_TYPE.PRIVATE_BUY || _auctionType == AUCTION_TYPE.DUTCH_FORWARD)
        {
            tvm.rawReserve(desiredPrice, 0); // reserve buy price, we don't want the change;
            _auctionSucceeded = true;
            
            // Update current buyer
            _currentBuyer    = msg.sender;
            _currentBuyPrice = desiredPrice;
            _currentBuyDT    = now;
        }

        // return the change
        msg.sender.transfer(0, true, 128);
    }
    
    //========================================
    //
    function _sendOutTheMoney() internal
    {
        if(_moneySentOut) { return; }

        // Calculate escrow fees;
        uint128 escrowFees = _currentBuyPrice / 10000 * _escrowPercent;
        uint128 finalPrice = _currentBuyPrice - escrowFees;

        // Send out the money;
        _sellerAddress.transfer(finalPrice, true, 0);
        _escrowAddress.transfer(escrowFees, true, 1);

        _moneySentOut = true;
    }

    //========================================
    /// @dev you can call "finalize" as many times as you want;
    //
    function finalize() external
    {
        require(now >= _dtEnd || _auctionSucceeded,   ERROR_AUCTION_IN_PROCESS);
        require(msg.value >= _feeValue,               ERROR_NOT_ENOUGH_MONEY  );
        if(_auctionType == AUCTION_TYPE.ENGLISH_BLIND)
        {
            require(now >= _dtRevealEnd, ERROR_PRICE_REVEAL_IN_PROCESS);
        }
        
        _reserve(); // reserve minimum balance;

        // No asset was ever received, 
        if(!_assetReceived) 
        { 
            // return the change
            msg.sender.transfer(0, true, 128);
            return;
        }

        // No bids were made, return asset to the owner;
        if(_currentBuyer == addressZero || !_auctionSucceeded)
        {
            _moneySentOut = true;  // No need to send out money in this case 
            checkAssetDelivered(); // Ensure that seller got the asset back
            return;
        }

        _sendOutTheMoney();

        // Transfer asset to a new owner;
        if(!_assetDelivered)
        {
            checkAssetDelivered(); // Ensure that buyer got the asset back
        }
        else
        {
            if(_moneySentOut)
            {
                // return the change with no fear
                msg.sender.transfer(0, true, 128);
            }
        }
    }

    //========================================
    //
    /*function destroy() external onlySeller
    {

    }*/

    //========================================
    //
    onBounce(TvmSlice slice) external pure
    {
		uint32 func = slice.decode(uint32);
		if(func == tvm.functionId(receiveAsset)) 
        {
            // TODO: failed to register asset
        }
    }

    //========================================
    // Called ONLY after auction is finished;
    function deliverAsset(address receiver) internal virtual;

    //========================================
    // Called ONLY after auction is finished;
    function checkAssetDelivered() internal virtual;
    
    //========================================
    // Called BEFORE auction is started;
    // That means we don't have any bids yet, only minimal balance;
    function receiveAsset() public virtual;
}

//================================================================================
//
