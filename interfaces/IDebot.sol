pragma ton-solidity >=0.42.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

//================================================================================
//
import "../interfaces/IOwnable.sol";
import "../interfaces/debot/address.sol";
import "../interfaces/debot/amount.sol";
import "../interfaces/debot/menu.sol";
import "../interfaces/debot/number.sol";
import "../interfaces/debot/sdk.sol";
import "../interfaces/debot/terminal.sol";

//================================================================================
//
interface IMsig 
{
    /// @dev Allows custodian if she is the only owner of multisig to transfer funds with minimal fees.
    /// @param dest Transfer target address.
    /// @param value Amount of funds to transfer.
    /// @param bounce Bounce flag. Set true if need to transfer funds to existing account;
    /// set false to create new account.
    /// @param flags `sendmsg` flags.
    /// @param payload Tree of cells used as body of outbound internal message.
    function sendTransaction(
        address dest,
        uint128 value,
        bool    bounce,
        uint8   flags,
        TvmCell payload) external view;
}

//================================================================================
//
abstract contract Debot is IOwnable
{
    //========================================
    // 
    uint8 constant    DEBOT_ABI = 1;
    uint8             _options;
    optional(bytes)   _icon;
    optional(string)  _debotAbi;
    optional(uint256) _emptyPk;

    //========================================
    //
    function start() public virtual;

    //========================================
    //
    function getVersion() public virtual returns (string name, uint24 semver);

    //========================================
    //
    function getDebotOptions() public view returns (uint8 options, string debotAbi, string targetAbi, address targetAddr) 
    {
        debotAbi   = _debotAbi.hasValue() ? _debotAbi.get() : "";
        targetAbi  = "";
        targetAddr = address(0);
        options    = _options;
    }

    //========================================
    //
    function setABI(string dabi) public 
    {
        require(tvm.pubkey() == msg.pubkey() || senderIsOwner(), ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER);
        tvm.accept();
        _options |= DEBOT_ABI;
        _debotAbi = dabi;
    }

    //========================================
    //
    function setIcon(bytes icon) public 
    {
        require(tvm.pubkey() == msg.pubkey() || senderIsOwner(), ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER);
        tvm.accept();
        _icon = icon;
    }

    //========================================
    //
    function onError(uint32 sdkError, uint32 exitCode) public virtual;
    
    //========================================
    //
    function _sendTransact(address msigAddr, address dest, TvmCell payload, uint128 grams) internal pure
    {
        IMsig(msigAddr).sendTransaction{
            abiVer: 2,
            extMsg: true,
            sign: true,
            callbackId: 0,
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            pubkey: 0x00
        }(dest,
          grams,
          false,
          1,
          payload);
    }

    //========================================
    //
}

//================================================================================
//
