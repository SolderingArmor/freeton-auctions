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
import "../contracts/AuctionManager.sol";
import "../interfaces/IDebot.sol";
import "../interfaces/IUpgradable.sol";

//================================================================================
//
contract AuctionDebot is Debot, Upgradable
{
    address _auctionManagerAddress;
    address _auctionAddress;
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
    function setFAuctionManagerAddress(address managerAddress) public 
    {
        require(msg.pubkey() == tvm.pubkey() || senderIsOwner(), ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER);
        tvm.accept();
        _auctionManagerAddress = managerAddress;
    }    

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
        //_eraseCtx();
        index = 0; // shut a warning

        if(_auctionManagerAddress == addressZero)
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

    function _createAuction_15(uint32 index) public
    {
        TvmCell body = tvm.encodeBody(AuctionManager.createAuction, _sellerAddress, _buyerAddress, _assetAddress, _auctionType, _dtStart,
                                                                    _feeValue, _minBid, _minPriceStep, _buyNowPrice, _dtEnd, _dtRevealEnd, _dutchCycle);
        _sendTransact(tvm.functionId(_createAuction_16), _msigAddress, _auctionManagerAddress, body, ATTACH_VALUE);
    }

    function _createAuction_16(address value) public
    {
        _fetchAuction_2(value);
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

    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    //
    /*function _listSymbols_1(uint32 index) public
    {
        index = 0; // shut a warning
        
        string text;
        for(Symbol symbol : _symbolsList)
        {
            if(text.byteLength() > 0){    text.append("\n");    }
            text.append(getSymbolRepresentation(symbol));
        }

        Terminal.print(0, text);

        _mainLoop(0);
    }

    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    //
    function _addSymbol_1(uint32 index) public
    {
        index = 0; // shut a warning
        AddressInput.get(tvm.functionId(_addSymbol_2), "Please enter TRC-6 RTW address: ");
    }

    function _addSymbol_2(address value) public
    {  
        TvmCell body = tvm.encodeBody(IDexFactory.addSymbol, value);
        _sendTransact(_msigAddress, _factoryAddress, body, ATTACH_VALUE);
        _addSymbol_3(0);
    }

    function _addSymbol_3(uint32 index) public
    {  
        index = 0; // shut a warning

        Terminal.print(0, "Adding symbol, please wait for ~10 seconds and refresh Symbols list");
        _mainLoop(0);
    }

    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    //
    function _getSymbolPair_1(uint32 index) public
    {
        index = 0; // shut a warning

        delete _selectedSymbol1;
        delete _selectedSymbol2;
        
        Terminal.print(0, "Please choose the first Symbol:");
        MenuItem[] mi;
        for(Symbol symbol : _symbolsList)
        {
            mi.push(MenuItem(getSymbolRepresentation(symbol), "", tvm.functionId(_getSymbolPair_2)));
        }
        Menu.select("Enter your choice: ", "", mi);
    }

    function _getSymbolPair_2(uint32 index) public
    {
        _selectedSymbol1 = _symbolsList[index];
        
        Terminal.print(0, "Please choose the second Symbol:");
        MenuItem[] mi;
        for(Symbol symbol : _symbolsList)
        {
            //if(symbol.addressRTW == _selectedSymbol1.addressRTW) {    continue;    }

            mi.push(MenuItem(getSymbolRepresentation(symbol), "", tvm.functionId(_getSymbolPair_3)));
        }
        Menu.select("Enter your choice: ", "", mi);
    }

    function _getSymbolPair_3(uint32 index) public
    {
        _selectedSymbol2 = _symbolsList[index];
        if(_selectedSymbol2.addressRTW == _selectedSymbol1.addressRTW)
        {
            Terminal.print(0, "You can't choose same Symbol twice!");
            _getSymbolPair_1(0);
            return;
        }

        //(_selectedSymbol1, _selectedSymbol2) = _sortSymbols(_selectedSymbol1, _selectedSymbol2);

        IDexFactory(_factoryAddress).getPairAddress{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_getSymbolPair_4),
                        onErrorId:  tvm.functionId(onError)
                        }(_selectedSymbol1.addressRTW, _selectedSymbol2.addressRTW);
    }

    function _getSymbolPair_4(address value) public
    {
        _symbolPairAddress = value;
        Sdk.getAccountType(tvm.functionId(_getSymbolPair_5), _symbolPairAddress);
    }

    function _getSymbolPair_5(int8 acc_type) public 
    {
        _symbolPairAccState = acc_type;
        _getSymbolPair_6(0);
    }

    function _getSymbolPair_6(uint32 index) public 
    {
        index = 0; // shut a warning

        if (_symbolPairAccState == -1 || _symbolPairAccState == 0) 
        {
            Terminal.print(0, format("Symbol Pair does not exist!"));

            MenuItem[] mi;
            mi.push(MenuItem("Deploy Pair", "", tvm.functionId(_symbolPairDeploy_1)));
            mi.push(MenuItem("<- Go back",  "", tvm.functionId(_mainLoop)          ));
            mi.push(MenuItem("<- Restart",  "", tvm.functionId(mainMenu)           ));
            Menu.select("Enter your choice: ", "", mi);
        }
        else if (_symbolPairAccState == 1)
        {
            _symbolPairMenu_1(0);
        } 
        else if (_symbolPairAccState == 2)
        {
            Terminal.print(0, format("Symbol Pair is FROZEN."));
            _mainLoop(0); 
        }
    }

    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    //
    function _symbolPairDeploy_1(uint32 index) public
    {
        index = 0; // shut a warning

        TvmCell body = tvm.encodeBody(IDexFactory.addPair, _selectedSymbol1.addressRTW, _selectedSymbol2.addressRTW);
        _sendTransact(_msigAddress, _factoryAddress, body, ATTACH_VALUE * 2);
        _symbolPairDeploy_2(1);
    }

    function _symbolPairDeploy_2(uint32 index) public
    {
        index = 0; // shut a warning
        Sdk.getAccountType(tvm.functionId(_symbolPairDeploy_3), _symbolPairAddress);
    }

    function _symbolPairDeploy_3(int8 acc_type) public
    {
        // Loop like crazy until we get the Pair
        if(acc_type == 1) {    _symbolPairMenu_1(0);    }
        else              {    _symbolPairDeploy_2(0);  }
    }
        
    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    //
    function _symbolPairMenu_1(uint32 index) public view
    {
        index = 0; // shut a warning

        ISymbolPair(_symbolPairAddress).getPairLiquidity{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_symbolPairMenu_2),
                        onErrorId:  tvm.functionId(onError)
                        }();
    }
    
    function _symbolPairMenu_2(Symbol symbol1, Symbol symbol2, uint256 liquidity, uint8 decimals) public
    {
        _selectedSymbol1 = symbol1;
        _selectedSymbol2 = symbol2;
        
        // TODO: show Pair info;
        string text1 = format("SYMBOL 1\nName: {}\nSymbol: {}\nDecimals: {}\nIn Pool: {}", symbol1.name, symbol1.symbol, symbol1.decimals, symbol1.balance);
        string text2 = format("SYMBOL 2\nName: {}\nSymbol: {}\nDecimals: {}\nIn Pool: {}", symbol2.name, symbol2.symbol, symbol2.decimals, symbol2.balance);
        string text3 = format("Liquidity: {}\nLiquidity decimals: {}", liquidity, decimals);

        Terminal.print(0, text1);
        Terminal.print(0, text2);
        Terminal.print(0, text3);

        MenuItem[] mi;
        mi.push(MenuItem("Trade",               "", tvm.functionId(_symbolPairTrade_1)                     ));
        mi.push(MenuItem("Provide liquidity",   "", tvm.functionId(_symbolPairProvideLiquidity_1)          ));
        mi.push(MenuItem("Get liquidity limbo", "", tvm.functionId(_symbolPairGetLiquidityLimbo_1)         ));
        mi.push(MenuItem("Deposit liquidity",   "", tvm.functionId(_symbolPairDepositLiquidity_1)          ));
        mi.push(MenuItem("Withdraw liquidity",  "", tvm.functionId(_symbolPairWithdrawLiquidity_1)         ));
        mi.push(MenuItem("Withdraw leftovers",  "", tvm.functionId(_symbolPairWithdrawLiquidityLeftovers_1)));

        mi.push(MenuItem("<- Go back", "", tvm.functionId(_mainLoop)          ));
        mi.push(MenuItem("<- Restart", "", tvm.functionId(mainMenu)           ));
        Menu.select("Enter your choice: ", "", mi);
    }

    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    // 
    function _symbolPairGetLiquidityLimbo_1(uint32 index) public view
    {
        index = 0; // shut a warning

        ISymbolPair(_symbolPairAddress).getUserLimbo{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_symbolPairGetLiquidityLimbo_2),
                        onErrorId:  tvm.functionId(onError)
                        }(_msigAddress);
    }

    function _symbolPairGetLiquidityLimbo_2(uint128 amount1, uint128 amount2) public
    {
        Terminal.print(0, format("Symbol1: {}\nSymbol2: {}", amount1, amount2));

        _symbolPairMenu_1(0);
    }
    
    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    // TODO: including wallet deployment
    function _symbolPairTrade_1(uint32 index) public
    {
        index = 0; // shut a warning

        delete _tradeSellSymbol;
        delete _tradeBuySymbol;

        Terminal.print(0, format("Select a symbol to sell:"));
        MenuItem[] mi;
        mi.push(MenuItem(getSymbolRepresentation(_selectedSymbol1), "", tvm.functionId(_symbolPairTrade_2) ));
        mi.push(MenuItem(getSymbolRepresentation(_selectedSymbol2), "", tvm.functionId(_symbolPairTrade_2) ));

        mi.push(MenuItem("<- Go back", "", tvm.functionId(_mainLoop) ));
        mi.push(MenuItem("<- Restart", "", tvm.functionId(mainMenu)  ));
        Menu.select("Enter your choice: ", "", mi);
    }

    function _symbolPairTrade_2(uint32 index) public
    {
        _tradeSellSymbol = (index == 0 ? _selectedSymbol1 : _selectedSymbol2);
        _tradeBuySymbol  = (index == 0 ? _selectedSymbol2 : _selectedSymbol1);

        ILiquidFTRoot(_tradeSellSymbol.addressRTW).getWalletAddress{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_symbolPairTrade_3),
                        onErrorId:  tvm.functionId(onError)
                        }(_msigAddress);
    }
    
    function _symbolPairTrade_3(address value) public
    {
        _tradeSellWalletAddress = value;
        Sdk.getAccountType(tvm.functionId(_symbolPairTrade_4), _tradeSellWalletAddress);
    }

    function _symbolPairTrade_4(int8 acc_type) public
    {
        if (acc_type == -1 || acc_type == 0) 
        {
            Terminal.print(0, format("You don't have a Token wallet, you can't trade!"));
            _symbolPairMenu_1(0); 
        }
        else if (acc_type == 1)
        {
            _symbolPairTrade_5(0);
        } 
        else if (acc_type == 2)
        {
            Terminal.print(0, format("Your Token wallet Wallet is FROZEN."));
            _mainLoop(0); 
        }
    }

    function _symbolPairTrade_5(uint32 index) public view
    {
        index = 0; // shut a warning

        ILiquidFTRoot(_tradeBuySymbol.addressRTW).getWalletAddress{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_symbolPairTrade_6),
                        onErrorId:  tvm.functionId(onError)
                        }(_msigAddress);
    }

    function _symbolPairTrade_6(address value) public
    {
        _tradeBuyWalletAddress = value;
        Sdk.getAccountType(tvm.functionId(_symbolPairTrade_7), _tradeBuyWalletAddress);
    }

    function _symbolPairTrade_7(int8 acc_type) public
    {
        if (acc_type == -1 || acc_type == 0) 
        {
            Terminal.print(0, format("Deploy receiver TTW first!"));
            TvmCell body = tvm.encodeBody(ILiquidFTRoot.createWallet, _msigAddress, addressZero, 0);
            _sendTransact(_msigAddress, _tradeBuySymbol.addressRTW, body, ATTACH_VALUE);
            _symbolPairTrade_8(0); 
        }
        else if (acc_type == 1)
        {
            _symbolPairTrade_8(0);
        } 
        else if (acc_type == 2)
        {
            Terminal.print(0, format("Your Token wallet Wallet is FROZEN."));
            _mainLoop(0); 
        }
    }

    function _symbolPairTrade_8(uint32 index) public
    {
        index = 0; // shut a warning
        AmountInput.get(tvm.functionId(_symbolPairTrade_9), format("Enter amount of {} to sell: ", _tradeSellSymbol.symbol), _tradeSellSymbol.decimals, 0, 999999999999999999999999999999);
    }

    function _symbolPairTrade_9(uint256 value) public
    {
        _sellAmount = uint128(value);

        ISymbolPair(_symbolPairAddress).getPrice{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_symbolPairTrade_10),
                        onErrorId:  tvm.functionId(onError)
                        }(_tradeSellSymbol.addressRTW, _sellAmount);
    }

    function _symbolPairTrade_10(uint128 amount, uint8 decimals) public
    {
        _buyAmount = amount;
        decimals = 0;  // shut a warning
        Terminal.print(0, format("You are selling {} amount of {} and will get {} amount of {} in return. OK?", _sellAmount, _tradeSellSymbol.symbol, _buyAmount, _tradeBuySymbol.symbol));

        MenuItem[] mi;
        mi.push(MenuItem("YES", "",             tvm.functionId(_symbolPairTrade_11) ));
        mi.push(MenuItem("Nah, get me out", "", tvm.functionId(_symbolPairMenu_1)   ));
        Menu.select("Enter your choice: ", "", mi);
    }

    function _symbolPairTrade_11(uint32 index) public view
    {
        index = 0; // shut a warning
        TvmBuilder builder;
        builder.store(uint8(0), _buyAmount, uint16(500)); // TODO: slippage is forced to 5%, ash user to enter number instead
        TvmCell body = tvm.encodeBody(ILiquidFTWallet.transfer, uint128(_sellAmount), _symbolPairAddress, _msigAddress, addressZero, builder.toCell());
        _sendTransact(_msigAddress, _tradeSellWalletAddress, body, ATTACH_VALUE);
        _symbolPairMenu_1(0);
    }
    
    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    //
    function _symbolPairProvideLiquidity_1(uint32 index) public
    {
        index = 0; // shut a warning
        delete _provideLiquiditySymbol;

        MenuItem[] mi;
        mi.push(MenuItem(getSymbolRepresentation(_selectedSymbol1), "", tvm.functionId(_symbolPairProvideLiquidity_2) ));
        mi.push(MenuItem(getSymbolRepresentation(_selectedSymbol2), "", tvm.functionId(_symbolPairProvideLiquidity_2) ));

        mi.push(MenuItem("<- Go back",  "", tvm.functionId(_mainLoop) ));
        mi.push(MenuItem("<- Restart",  "", tvm.functionId(mainMenu)  ));
        Menu.select("Enter your choice: ", "", mi);
    }

    function _symbolPairProvideLiquidity_2(uint32 index) public
    {
        _provideLiquiditySymbol = (index == 0 ? _selectedSymbol1 : _selectedSymbol2);

        ILiquidFTRoot(_provideLiquiditySymbol.addressRTW).getWalletAddress{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_symbolPairProvideLiquidity_3),
                        onErrorId:  tvm.functionId(onError)
                        }(_msigAddress);
    }

    function _symbolPairProvideLiquidity_3(address value) public
    {
        _provideLiquidityWalletAddress = value;
        Sdk.getAccountType(tvm.functionId(_symbolPairProvideLiquidity_4), _provideLiquidityWalletAddress);
    }

    function _symbolPairProvideLiquidity_4(int8 acc_type) public
    {
        if (acc_type == -1 || acc_type == 0) 
        {
            Terminal.print(0, format("You don't have a Token wallet!"));
            _symbolPairMenu_1(0); 
        }
        else if (acc_type == 1)
        {
            _symbolPairProvideLiquidity_5(0);
        } 
        else if (acc_type == 2)
        {
            Terminal.print(0, format("Your Token wallet Wallet is FROZEN."));
            _mainLoop(0); 
        }
    }

    function _symbolPairProvideLiquidity_5(uint32 index) public
    {
        index = 0; // shut a warning
        
        AmountInput.get(tvm.functionId(_symbolPairProvideLiquidity_6), format("Enter amount of {} to deposit: ", _provideLiquiditySymbol.symbol), _provideLiquiditySymbol.decimals, 0, 999999999999999999999999999999);
    }

    function _symbolPairProvideLiquidity_6(uint256 value) public view
    {
        TvmBuilder builder;
        builder.store(uint8(1), uint128(0), uint16(0));
        TvmCell body = tvm.encodeBody(ILiquidFTWallet.transfer, uint128(value), _symbolPairAddress, _msigAddress, addressZero, builder.toCell());
        _sendTransact(_msigAddress, _provideLiquidityWalletAddress, body, ATTACH_VALUE);
        _symbolPairMenu_1(0);
    }
    
    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    // TODO: including LP wallet deployment
    function _symbolPairDepositLiquidity_1(uint32 index) public view
    {
        index = 0; // shut a warning

        ILiquidFTRoot(_symbolPairAddress).getWalletAddress{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_symbolPairDepositLiquidity_2),
                        onErrorId:  tvm.functionId(onError)
                        }(_msigAddress);
    }
    
    function _symbolPairDepositLiquidity_2(address value) public
    {
        _lpWalletAddress = value;
        Sdk.getAccountType(tvm.functionId(_symbolPairDepositLiquidity_3), _lpWalletAddress);
    }

    function _symbolPairDepositLiquidity_3(int8 acc_type) public
    {
        if (acc_type == -1 || acc_type == 0) 
        {
            // TODO: notify that we are deploying LP wallet; +
            //       also, check that wallet was created;
            Terminal.print(0, "You don't have LP wallet, deploy?");

            TvmCell body = tvm.encodeBody(ILiquidFTRoot.createWallet, _msigAddress, addressZero, 0);
            _sendTransact(_msigAddress, _symbolPairAddress, body, ATTACH_VALUE);
            _symbolPairDepositLiquidity_4(0);
        }
        else if (acc_type == 1)
        {
            _symbolPairDepositLiquidity_4(0);
        } 
        else if (acc_type == 2)
        {
            Terminal.print(0, format("Your LP Wallet is FROZEN."));
            _mainLoop(0); 
        }
    }

    function _symbolPairDepositLiquidity_4(uint32 index) public
    {
        index = 0; // shut a warning
        AmountInput.get(tvm.functionId(_symbolPairDepositLiquidity_5), format("Enter amount of {} to deposit: ", _selectedSymbol1.symbol), _selectedSymbol1.decimals, 0, 999999999999999999999999999999);
    }

    function _symbolPairDepositLiquidity_5(uint256 value) public
    {
        _depositAmount1 = uint128(value);
        AmountInput.get(tvm.functionId(_symbolPairDepositLiquidity_6), format("Enter amount of {} to deposit: ", _selectedSymbol2.symbol), _selectedSymbol2.decimals, 0, 999999999999999999999999999999);
    }

    function _symbolPairDepositLiquidity_6(uint256 value) public
    {
        _depositAmount2 = uint128(value);
        AmountInput.get(tvm.functionId(_symbolPairDepositLiquidity_7), "Enter Slippage in %: ", 2, 0, 10000);
    }

    function _symbolPairDepositLiquidity_7(uint256 value) public
    {
        _depositSlippage = uint16(value);
        
        // TODO: text?
        TvmCell body = tvm.encodeBody(ISymbolPair.depositLiquidity, _depositAmount1, _depositAmount2, uint16(_depositSlippage));
        _sendTransact(_msigAddress, _symbolPairAddress, body, ATTACH_VALUE);

        _symbolPairMenu_1(0);
    }
    
    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    // TODO: we catually can be missing TTWs if we just bought liquidity tokens
    function _symbolPairWithdrawLiquidity_1(uint32 index) public view
    {
        index = 0; // shut a warning

        ILiquidFTRoot(_symbolPairAddress).getWalletAddress{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_symbolPairWithdrawLiquidity_2),
                        onErrorId:  tvm.functionId(onError)
                        }(_msigAddress);
    }

    function _symbolPairWithdrawLiquidity_2(address value) public
    {
        _lpWalletAddress = value;
        Sdk.getAccountType(tvm.functionId(_symbolPairWithdrawLiquidity_3), _lpWalletAddress);
    }

    function _symbolPairWithdrawLiquidity_3(int8 acc_type) public
    {
        if (acc_type == -1 || acc_type == 0) 
        {
            // TODO: notify that we are deploying LP wallet; +
            //       also, check that wallet was created;
            Terminal.print(0, "Oops, looks like you don't have LP wallet, that means you don't have liquidity to withdraw (sorry bout that).");
            _symbolPairMenu_1(0);
        }
        else if (acc_type == 1)
        {
            _symbolPairWithdrawLiquidity_4(0);
        } 
        else if (acc_type == 2)
        {
            Terminal.print(0, format("Your LP Wallet is FROZEN (oopsie)."));
            _symbolPairMenu_1(0);
        }
    }

    function _symbolPairWithdrawLiquidity_4(uint32 index) public view
    {
        index = 0; // shut a warning

        ILiquidFTWallet(_lpWalletAddress).getBalance{
                        abiVer: 2,
                        extMsg: true,
                        sign: false,
                        time: uint64(now),
                        expire: 0,
                        pubkey: _emptyPk,
                        callbackId: tvm.functionId(_symbolPairWithdrawLiquidity_5),
                        onErrorId:  tvm.functionId(onError)
                        }();
    }

    function _symbolPairWithdrawLiquidity_5(uint128 balance) public
    {
        Terminal.print(0, format("You currently have {} Liquidity tokens.", balance));
        AmountInput.get(tvm.functionId(_symbolPairWithdrawLiquidity_6), "Enter amount to withdraw: ", 18, 0, 999999999999999999999999999999);
    }
    
    function _symbolPairWithdrawLiquidity_6(int256 value) public view
    {
        TvmCell body = tvm.encodeBody(ILiquidFTWallet.burn, uint128(value));
        _sendTransact(_msigAddress, _lpWalletAddress, body, ATTACH_VALUE);

        _symbolPairMenu_1(0); // TODO: other menu? maybe some message?
    }
    
    //========================================
    //========================================
    //========================================
    //========================================
    //========================================
    //
    function _symbolPairWithdrawLiquidityLeftovers_1(uint32 index) public view
    {
        index = 0; // shut a warning

        TvmCell body = tvm.encodeBody(ISymbolPair.collectLiquidityLeftovers);
        _sendTransact(_msigAddress, _symbolPairAddress, body, ATTACH_VALUE);

        _symbolPairMenu_1(0); // TODO: other menu? maybe some message?
    }*/







    //========================================
    //
    // 1. main menu: add symbol, get symbol pair to trade
    // 2.1. if adding symbol, enter rtw address;
    // 2.2. after entering send transaction and go to main menu
    // 3.1. if getting symbol, show list of symbols to choose 1st
    // 3.2. show list of symbols to choose 2nd
    // 3.3. check if pair exists, if it doesn't ask to deploy it
    // 3.4. if pair exists get pair information and show current info.
    // 4. get three wallets silently (we need to know if user has wallet A, wallet B and liquidity wallet)
    // 4. you need to choose, buy, sell, deposit, finalize or withdraw leftovers;
    // 4.1. if depositing, if walletA or walletB doesn't exist, say you can't deposit without wallets and go to menu 4;
    // 4.3. ask to send amount of symbol A
    // 4.4. ask to send amount of symbol B
    // 4.5. if finalizing, ask to create LP wallet if it doesn't exist;
    // 4.6. if finalizing, show current leftovers and pair ratio ask the amount symbol A to deposit;
    // 4.7. calculate symbol B based on amount, ask what slippage is good;
    // 4.8. send finalize;
    // 5. if buying, ask to create wallets that you don't have before that;
    // 5.1. after that ask for the amount to buy;
    // 5.2. ask for the slippage to buy;
    // 5.3. send transaction;
    // 6. if withdraw leftovers, we know that both wallets exist, just do that;

    
}

//================================================================================
//