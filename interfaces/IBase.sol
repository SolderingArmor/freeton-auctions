pragma ton-solidity >= 0.44.0;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;

//================================================================================
//
abstract contract IBase
{
    //========================================
    // Constants
    address constant addressZero = address.makeAddrStd(0, 0);

    //========================================
    // Modifiers
    function _reserve() internal inline view {    tvm.rawReserve(gasToValue(10000, address(this).wid), 0);    }
    modifier  reserve     {    _reserve();    _;                                       }
    modifier  returnChange{                   _; msg.sender.transfer(0, true, 128);    }
}

//================================================================================
//
