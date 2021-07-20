#!/usr/bin/env python3

# ==============================================================================
#
import freeton_utils
from   freeton_utils import *

class AuctionDnsRecord(object):
    def __init__(self, 
        tonClient: TonClient, 
        # statics
        sellerAddress: str, 
        buyerAddress: str, 
        assetAddress: str, 
        auctionType: int, 
        dtStart: int, 
        # constructor
        escrowAddress: str, 
        escrowPercent: int, 
        feeValue: int,
        minBid: int, 
        minPriceStep: int, 
        buyNowPrice: int, 
        dtEnd: int, 
        dtRevealEnd: int, 
        dutchCycle: int,
        signer: Signer = None):
        self.SIGNER      = generateSigner() if signer is None else signer
        self.TONCLIENT   = tonClient
        self.ABI         = "../bin/AuctionDnsRecord.abi.json"
        self.TVC         = "../bin/AuctionDnsRecord.tvc"
        self.TVC_BID     = "../bin/AuctionBid.tvc"
        self.CODE        = getCodeFromTvc(self.TVC)
        self.CONSTRUCTOR = {
            "escrowAddress":escrowAddress, "escrowPercent":escrowPercent, "feeValue":feeValue,
            "minBid":minBid,               "minPriceStep":minPriceStep,   "buyNowPrice":buyNowPrice,
            "dtEnd":dtEnd,                 "dtRevealEnd":dtRevealEnd,     "dutchCycle":dutchCycle
            }
        self.INITDATA    = {
            "_sellerAddress":sellerAddress, "_buyerAddress":buyerAddress,   "_assetAddress":assetAddress,   
            "_auctionType":auctionType, "_dtStart":dtStart, "_bidCode":getCodeFromTvc(self.TVC_BID)
            }
        self.PUBKEY      = ZERO_PUBKEY
        self.ADDRESS     = getAddressZeroPubkey(abiPath=self.ABI, tvcPath=self.TVC, initialData=self.INITDATA)

    def deploy(self):
        result = deployContract(tonClient=self.TONCLIENT, abiPath=self.ABI, tvcPath=self.TVC, constructorInput=self.CONSTRUCTOR, initialData=self.INITDATA, signer=self.SIGNER, initialPubkey=self.PUBKEY)
        return result

    def _call(self, functionName, functionParams, signer):
        result = callFunction(tonClient=self.TONCLIENT, abiPath=self.ABI, contractAddress=self.ADDRESS, functionName=functionName, functionParams=functionParams, signer=signer)
        return result

    def _callFromMultisig(self, msig: SetcodeMultisig, functionName, functionParams, value, flags):
        messageBoc = prepareMessageBoc(abiPath=self.ABI, functionName=functionName, functionParams=functionParams)
        result     = msig.callTransfer(addressDest=self.ADDRESS, value=value, payload=messageBoc, flags=flags)
        return result

    def _run(self, functionName, functionParams):
        result = runFunction(tonClient=self.TONCLIENT, abiPath=self.ABI, contractAddress=self.ADDRESS, functionName=functionName, functionParams=functionParams)
        return result

    # ========================================
    #
    def cancelAuction(self, msig: SetcodeMultisig, value: int):
        result = self._callFromMultisig(msig=msig, functionName="cancelAuction", functionParams={}, value=value, flags=1)
        return result

    
    def bid(self, msig: SetcodeMultisig, value: int):
        result = self._callFromMultisig(msig=msig, functionName="bid", functionParams={}, value=value, flags=1)
        return result

    def finalize(self, msig: SetcodeMultisig, value: int):
        result = self._callFromMultisig(msig=msig, functionName="finalize", functionParams={}, value=value, flags=1)
        return result

    def receiveAsset(self, msig: SetcodeMultisig, value: int):
        result = self._callFromMultisig(msig=msig, functionName="receiveAsset", functionParams={}, value=value, flags=1)
        return result

    # ========================================
    #
    def getInfo(self):
        result = self._run(functionName="getInfo", functionParams={})
        return result

    def getDesiredPrice(self):
        result = self._run(functionName="getDesiredPrice", functionParams={})
        return result

# ==============================================================================
# 
