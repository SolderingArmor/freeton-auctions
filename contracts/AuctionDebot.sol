pragma ton-solidity >=0.44.0;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;

//================================================================================
//
/// @title AuctionDebot
/// @author SuperArmor
/// @notice Debot for Auctions

//================================================================================
//
import "../interfaces/IAuctionManager.sol";
import "../interfaces/IDebot.sol";
import "../interfaces/IUpgradable.sol";

//================================================================================
//
contract AuctionDebot is Debot, Upgradable
{
    address _auctionManagerAddress;
    address _auctionAddress;
    TvmCell _auctionCode;
    address _msigAddress;
    
    address      _escrowAddress;    // escrow multisig for collecting fees;
    uint16       _escrowPercent;    // times 100; 1% = 100, 10% = 1000;
    address      _sellerAddress;    // seller is the real asset owner;
    address      _buyerAddress;     // buyer is specified only when "_type" is AUCTION_TYPE.PRIVATE_BUY, otherwise 0:0000000000000000000000000000000000000000000000000000000000000000;
    address      _assetAddress;     // asset contract address;
    AUCTION_TYPE _auctionType;      //
    TvmCell      _bidCode;          //
    uint128      _feeValue;         //
    uint128      _minBid;           // for English it is minimum price, for Dutch it is maximum price;
    uint128      _minPriceStep;     //
    uint128      _buyNowPrice;      //
    uint32       _dtStart;          //
    uint32       _dtEnd;            //
    uint32       _dtRevealEnd;      //
    uint32       _dutchCycle;       // Period of time for Dutch auctions when the price decresaes by _minPriceStep value;

    bool         _assetReceived;    //
    bool         _auctionStarted;   //
    bool         _auctionSucceeded; //
    bool         _moneySentOut;     //
    bool         _assetDelivered;   //

    address      _currentBuyer;     //
    uint128      _currentBuyPrice;  //
    uint32       _currentBuyDT;     //
    uint128      _currentBlindBets; //

    uint128 constant ATTACH_VALUE = 0.5 ton;

	//========================================
    //
    constructor(address ownerAddress) public 
    {
        _ownerAddress = ownerAddress;
        tvm.accept();
    }
    
    //========================================
    //
    function setAuctionManagerAddress(address managerAddress) public 
    {
        require(msg.pubkey() == tvm.pubkey() || senderIsOwner(), ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER);
        tvm.accept();
        _auctionManagerAddress = managerAddress;
    }
    
    //========================================
    //
    function setAuctionCode(TvmCell code) public 
    {
        require(msg.pubkey() == tvm.pubkey() || senderIsOwner(), ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER);
        tvm.accept();
        _auctionCode = code;
    }

    //========================================
    //
    /*function calculateAuctionInit(address sellerAddress, address buyerAddress, address assetAddress, AUCTION_TYPE auctionType, uint32 dtStart) public view returns (address, TvmCell)
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
    }*/

	//========================================
    //
	function getRequiredInterfaces() public pure returns (uint256[] interfaces) 
    {
        return [Terminal.ID, AddressInput.ID, NumberInput.ID, AmountInput.ID, Menu.ID];
	}

    //========================================
    //
    function getDebotInfo() public functionID(0xDEB) view returns(string name,     string version, string publisher, string key,  string author,
                                                                  address support, string hello,   string language,  string dabi, bytes icon)
    {
        name      = "Auction DeBot (SuperArmor)";
        version   = "0.1.0";
        publisher = "@SuperArmor";
        key       = "Auction DeBot from SuperArmor";
        author    = "@SuperArmor";
        support   = addressZero;
        hello     = "Welcome to SuperArmor's Auction DeBot!";
        language  = "en";
        dabi      = _debotAbi.hasValue() ? _debotAbi.get() : "";
        icon      = _icon.hasValue()     ? _icon.get()     : "";
    }

    //========================================
    /// @notice Define DeBot version and title here.
    function getVersion() public override returns (string name, uint24 semver) 
    {
        (name, semver) = ("Auction DeBot", _version(0, 2, 0));
    }

    function _version(uint24 major, uint24 minor, uint24 fix) private pure inline returns (uint24) 
    {
        return (major << 16) | (minor << 8) | (fix);
    }    

    //========================================
    // Implementation of Upgradable
    function onCodeUpgrade() internal override 
    {
        tvm.resetStorage();
    }

    //========================================
    //
    function onError(uint32 sdkError, uint32 exitCode) public override
    {
        {
            Terminal.print(0, format("Failed! SDK Error: {}. Exit Code: {}", sdkError, exitCode));
        }     

        mainMenu(0); 
    }

    //========================================
    /// @notice Entry point function for DeBot.    
    function start() public override 
    {
        mainEnterDialog(0);
    }

    //========================================
    //
    function mainEnterDialog(uint32 index) public 
    {
        index = 0; // shut a warning

        if(_auctionManagerAddress == addressZero || _auctionCode.toSlice().empty())
        {
            Terminal.print(0, "DeBot is being upgraded.\nPlease come back in a minute.\nSorry for inconvenience.");
            return;
        }

        AddressInput.get(tvm.functionId(onMsigEnter), "Let's start with entering your Multisig Wallet address: ");
    }

    //========================================
    //
    function onMsigEnter(address value) public
    {  
        _msigAddress = value;
        mainMenu(0);
    }

    function mainMenu(uint32 index) public 
    {
        index = 0; // shut a warning

        MenuItem[] mi;
        mi.push(MenuItem("Create auction",          "", tvm.functionId(_createAuction_1) ));
        mi.push(MenuItem("Manage existing auction", "", tvm.functionId(_fetchAuction_1)  ));
        mi.push(MenuItem("<- Restart",              "", tvm.functionId(mainEnterDialog)  ));
        Menu.select("Enter your choice: ", "", mi);
    }

    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    //
    function _createAuction_1(uint32 index) public
    {
        index = 0; // shut a warning

        MenuItem[] mi;
        mi.push(MenuItem("ENGLISH_FORWARD", "", tvm.functionId(_createAuction_2) ));
        mi.push(MenuItem("ENGLISH_BLIND",   "", tvm.functionId(_createAuction_2) ));
        mi.push(MenuItem("DUTCH_FORWARD",   "", tvm.functionId(_createAuction_2) ));
        mi.push(MenuItem("PUBLIC_BUY",      "", tvm.functionId(_createAuction_2) ));
        mi.push(MenuItem("PRIVATE_BUY",     "", tvm.functionId(_createAuction_2) ));
        mi.push(MenuItem("<- Back",         "", tvm.functionId(mainMenu)         ));
        mi.push(MenuItem("<- Restart",      "", tvm.functionId(mainEnterDialog)  ));
        Menu.select("Select auction type: ", "", mi);        
    }

    function _createAuction_2(uint32 index) public
    {
        _auctionType = AUCTION_TYPE(index);

        _escrowAddress = addressZero; //
        _escrowPercent = 0;           //
        _sellerAddress = addressZero; //
        _buyerAddress  = addressZero; //
        _assetAddress  = addressZero; //
        _feeValue      = 0;           //
        _minBid        = 0;           //
        _minPriceStep  = 0;           //
        _buyNowPrice   = 0;           //
        _dtStart       = 0;           //
        _dtEnd         = 0;           //
        _dtRevealEnd   = 0;           //
        _dutchCycle    = 0;           //

        AddressInput.get(tvm.functionId(_createAuction_3), "Enter seller (asset owner) Wallet address: ");
    }

    function _createAuction_3(address value) public // _sellerAddress
    {
        _sellerAddress = value;
        if(_auctionType == AUCTION_TYPE.PRIVATE_BUY)
        {
            AddressInput.get(tvm.functionId(_createAuction_4), "Enter buyer Wallet address: ");
        }
        else
        {
            AddressInput.get(tvm.functionId(_createAuction_5), "Enter asset address: ");
        }
    }
    
    function _createAuction_4(address value) public // _buyerAddress
    {
        _buyerAddress = value;
        AddressInput.get(tvm.functionId(_createAuction_5), "Enter asset address: ");
    }
    
    function _createAuction_5(address value) public // _assetAddress
    {
        _assetAddress = value;
        AmountInput.get(tvm.functionId(_createAuction_6), "Enter minimum contract fee: ", 9, 100000000, 999999999999999999999999999999);
    }

    function _createAuction_6(uint128 value) public // _feeValue
    {
        _feeValue = value;
        AmountInput.get(tvm.functionId(_createAuction_7), "Enter starting bid: ", 9, 1, 999999999999999999999999999999);
    }

    function _createAuction_7(uint128 value) public // _minBid
    {
        _minBid = value;
        if(_auctionType == AUCTION_TYPE.ENGLISH_BLIND)
        {
            NumberInput.get(tvm.functionId(_createAuction_10), "Enter auction satrt date (seconds from now):", 0, 999999999999999999999999999999);
        }
        else if(_auctionType == AUCTION_TYPE.DUTCH_FORWARD)
        {
            AmountInput.get(tvm.functionId(_createAuction_8), "Enter price step: ", 9, 1, _minBid);
        }
        else if(_auctionType == AUCTION_TYPE.ENGLISH_FORWARD)
        {
            AmountInput.get(tvm.functionId(_createAuction_8), "Enter price step: ", 9, 1, 999999999999999999999999999999);
        }
        else if(_auctionType == AUCTION_TYPE.PRIVATE_BUY || _auctionType == AUCTION_TYPE.PUBLIC_BUY)
        {
            AmountInput.get(tvm.functionId(_createAuction_9), "Enter buy now price: ", 9, _minBid+1, 999999999999999999999999999999);
        }
    }

    function _createAuction_8(uint128 value) public // _minPriceStep
    {
        _minPriceStep = value;
        if(_auctionType == AUCTION_TYPE.DUTCH_FORWARD)
        {
            _buyNowPrice = 0;
            NumberInput.get(tvm.functionId(_createAuction_10), "Enter auction start date (seconds from now):", 0, 999999999999999999999999999999);
        }
        else
        {
            AmountInput.get(tvm.functionId(_createAuction_9), "Enter buy now price: ", 9, _minBid+1, 999999999999999999999999999999);
        }
    }

    function _createAuction_9(uint128 value) public // _buyNowPrice
    {
        _buyNowPrice = value;
        NumberInput.get(tvm.functionId(_createAuction_10), "Enter auction start date (seconds from now):", 0, 999999999999999999999999999999);
    }

    function _createAuction_10(int256 value) public // _dtStart
    {
        _dtStart = uint32(value);
        NumberInput.get(tvm.functionId(_createAuction_11), "Enter auction duration (seconds from start):", 1, 60*60*24*60);
    }

    function _createAuction_11(int256 value) public // _dtEnd
    {
        _dtEnd = _dtStart + uint32(value);
        if(_auctionType == AUCTION_TYPE.ENGLISH_BLIND)
        {
            NumberInput.get(tvm.functionId(_createAuction_12), "Enter auction price reveal duration (seconds from end):", 1, 60*60*24*7);
        }
        else if(_auctionType == AUCTION_TYPE.DUTCH_FORWARD)
        {
            NumberInput.get(tvm.functionId(_createAuction_13), "Enter auction time step when price decreases (in seconds):", 1, _dtEnd-_dtStart);
        }
        else
        {
            _createAuction_14(0);
        }
    }

    function _createAuction_12(int256 value) public // _dtRevealEnd
    {
        _dtRevealEnd = _dtEnd + uint32(value);
        _createAuction_14(0);
    }

    function _createAuction_13(int256 value) public // _dutchCycle
    {
        _dutchCycle = uint32(value);
        _createAuction_14(0);
    }

    function _createAuction_14(uint32 index) public
    {
        // TODO: please revise everything and say, deploy or not
    }

    function _createAuction_15(uint32 index) public view
    {
        index = 0; // shut a warning
        TvmCell body = tvm.encodeBody(IAuctionManager.createAuction, _sellerAddress, _buyerAddress, _assetAddress, _auctionType, _dtStart,
                                                                     _feeValue, _minBid, _minPriceStep, _buyNowPrice, _dtEnd, _dtRevealEnd, _dutchCycle);
        _sendTransact(0, _msigAddress, _auctionManagerAddress, body, ATTACH_VALUE);

        IAuctionManager(_auctionManagerAddress).calculateAuctionInit{
                abiVer: 2,
                extMsg: true,
                sign: false,
                time: uint64(now),
                expire: 0,
                pubkey: _emptyPk,
                callbackId: tvm.functionId(_createAuction_16),
                onErrorId:  tvm.functionId(_fetchAuction_Error)
                }(_sellerAddress, _buyerAddress, _assetAddress, _auctionType, _dtStart);
    }

    function _createAuction_16(address auctionAddress, TvmCell auctionInit) public 
    {
        auctionInit.toSlice(); // shut a warning
        _fetchAuction_2(auctionAddress);
    }
    

    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    //
    function _fetchAuction_Error(uint32 sdkError, uint32 exitCode) public
    {
        sdkError = 0; // shut a warning
        exitCode = 0; // shut a warning
        Terminal.print(0, "Auction not found! \nLet's start from the beginning.");
        mainMenu(0);
    }
    
    function _fetchAuction_1(uint32 index) public
    {
        index = 0; // shut a warning
        AddressInput.get(tvm.functionId(_fetchAuction_2), "Enter auction address: ");
    }

    function _fetchAuction_2(address value) public
    {
        _auctionAddress = value;

        IAuction(_auctionAddress).getInfo{
                abiVer: 2,
                extMsg: true,
                sign: false,
                time: uint64(now),
                expire: 0,
                pubkey: _emptyPk,
                callbackId: tvm.functionId(_fetchAuction_3),
                onErrorId:  tvm.functionId(_fetchAuction_Error)
                }();
    }

    function _fetchAuction_3(address      escrowAddress,
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
                             uint128      currentBlindBets) public 
    {
        _escrowAddress    = escrowAddress;
        _escrowPercent    = escrowPercent;
        _sellerAddress    = sellerAddress;
        _buyerAddress     = buyerAddress;
        _assetAddress     = assetAddress;
        _auctionType      = auctionType;
        _minBid           = minBid;
        _minPriceStep     = minPriceStep;
        _buyNowPrice      = buyNowPrice;
        _dtStart          = dtStart;
        _dtEnd            = dtEnd;
        _dtRevealEnd      = dtRevealEnd;
        _dutchCycle       = dutchCycle;
        _assetReceived    = assetReceived;
        _auctionStarted   = auctionStarted;
        _auctionSucceeded = auctionSucceeded;
        _moneySentOut     = moneySentOut;
        _assetDelivered   = assetDelivered;
        _currentBuyer     = currentBuyer;
        _currentBuyPrice  = currentBuyPrice;
        _currentBuyDT     = currentBuyDT;
        _currentBlindBets = currentBlindBets;

        _fetchAuction_4(0);
    }

    function _fetchAuction_4(uint32 index) public
    {
        index = 0; // shut a warning
        //what would you like to do? bid, finalize etc
    }

}

//================================================================================
//