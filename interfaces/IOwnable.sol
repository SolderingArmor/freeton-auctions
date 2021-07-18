pragma ton-solidity >= 0.44.0;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;

//================================================================================
//
import "../interfaces/IBase.sol";

//================================================================================
//
abstract contract IOwnable is IBase
{
    //========================================
    // Error codes
    uint constant ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER = 100;
    
    //========================================
    // Variables
    address _ownerAddress; //

    //========================================
    // Modifiers
    function senderIsOwner() internal view inline returns (bool) { return (msg.sender.isStdAddrWithoutAnyCast() && _ownerAddress == msg.sender && _ownerAddress != addressZero);    }
    modifier onlyOwner {    require(senderIsOwner(), ERROR_MESSAGE_SENDER_IS_NOT_MY_OWNER);    _;    }

    //========================================
    // Getters
    function  getOwnerAddress()   external             view         returns (address)  {    return                      (_ownerAddress);    }
    function callOwnerAddress()   external responsible view reserve returns (address)  {    return {value: 0, flag: 128}(_ownerAddress);    }

    //========================================
    // 
    function changeOwner(address newOwnerAddress) external onlyOwner reserve returnChange
    {
        _ownerAddress = newOwnerAddress;
    }

    //========================================
    // 
    function callChangeOwner(address newOwnerAddress) external responsible onlyOwner returns (address)
    {
        _reserve();
        _ownerAddress = newOwnerAddress;

        // Return the change
        return {value: 0, flag: 128}(newOwnerAddress);
    }
}

//================================================================================
//