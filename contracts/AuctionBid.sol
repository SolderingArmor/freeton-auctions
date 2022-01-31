pragma ton-solidity >=0.52.0;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;

//================================================================================
//
import "../interfaces/IBase.sol";

//================================================================================
//
contract AuctionBid is IBase
{
    //========================================
    // Error codes
    uint constant ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER = 100;
    uint constant ERROR_NOT_ENOUGH_MONEY               = 200;

    //========================================
    // Variables
    address static _auctionAddress; // 
    address static _bidderAddress;  // 
    uint128        _feeValue;       //
    uint256        _priceHash;      //
    uint32         _dt;             //
    
    //========================================
    // Modifiers
    modifier  onlyAuction {    require(_checkSenderAddress(_auctionAddress), ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER);    _; }
    function _reserveFee() internal inline view {    tvm.rawReserve(_feeValue, 0);    }
    modifier  reserveFee  {    if(msg.isInternal){ _reserve(); }    _;    }

    //========================================
    //
    constructor(uint128 feeValue) public onlyAuction reserveFee
    { 
        _feeValue = feeValue;
        _dt       = now;

        _bidderAddress.transfer(0, true, 128); // return change to bidder
    }

    //========================================
    //
    function setPriceHash(uint256 priceHash) external onlyAuction reserveFee returnChangeTo(_bidderAddress)
    {
        require(address(this).balance > _feeValue, ERROR_NOT_ENOUGH_MONEY);
        _priceHash = priceHash;
    }

    //========================================
    //
    function revealPriceHash(uint128 price, uint256 salt) external view responsible onlyAuction returns (uint128 revealedPrice, 
                                                                                                         uint256 revealedSalt, 
                                                                                                         uint256 revealedHash, 
                                                                                                         uint256 actualHash, 
                                                                                                         address bidderAddress)
    {
        TvmBuilder builder;
        builder.store(price);
        builder.store(salt);
        TvmCell cell = builder.toCell();
        uint256 newHash = tvm.hash(cell);

        if(newHash == _priceHash)
        {
            return{value: 0, flag: 128+32, bounce: false}(price, salt, newHash, _priceHash, _bidderAddress);
        }
        else
        {
            _reserve();
            return{value: 0, flag: 128, bounce: false}(price, salt, newHash, _priceHash, _bidderAddress);
        }
    }

    //========================================
    //
    function getInfo() external view returns (address auctionAddress, 
                                              address bidderAddress, 
                                              uint128 feeValue, 
                                              uint256 priceHash, 
                                              uint32  dt)
    {
        return(_auctionAddress, _bidderAddress, _feeValue, _priceHash, _dt);
    }
}

//================================================================================
//