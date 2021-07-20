#!/usr/bin/env python3

# ==============================================================================
#
import freeton_utils
from   freeton_utils import *

class AuctionManagerDnsRecord(object):
    def __init__(self, tonClient: TonClient, ownerAddress: str, bidCode: str, auctionCode: str, signer: Signer = None):
        self.SIGNER      = generateSigner() if signer is None else signer
        self.TONCLIENT   = tonClient
        self.ABI         = "../bin/AuctionManagerDnsRecord.abi.json"
        self.TVC         = "../bin/AuctionManagerDnsRecord.tvc"
        self.CODE        = getCodeFromTvc(self.TVC)
        self.CONSTRUCTOR = {"ownerAddress":ownerAddress}
        self.INITDATA    = {"_bidCode":bidCode, "_auctionCode":auctionCode}
        self.PUBKEY      = self.SIGNER.keys.public
        self.ADDRESS     = getAddress(abiPath=self.ABI, tvcPath=self.TVC, signer=self.SIGNER, initialPubkey=self.PUBKEY, initialData=self.INITDATA)

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
    def createAuctionDnsRecord(self, msig: SetcodeMultisig, value: int, 
        sellerAddress: str, buyerAddress: str, assetAddress: str, auctionType: int, dtStart: int,
        feeValue: int, minBid: int, minPriceStep: int, buyNowPrice: int, dtEnd: int, dtRevealEnd: int, dutchCycle: int):

        result = self._callFromMultisig(msig=msig, functionName="createAuction", functionParams={
            "sellerAddress":sellerAddress, "buyerAddress":buyerAddress, "assetAddress":assetAddress, "auctionType":auctionType, "dtStart":dtStart,
            "feeValue":feeValue, "minBid":minBid, "minPriceStep":minPriceStep, "buyNowPrice":buyNowPrice, "dtEnd":dtEnd, "dtRevealEnd":dtRevealEnd, "dutchCycle":dutchCycle}, 
            value=value, flags=1)
        return result
    
    # ========================================
    #
    def getHashFromPrice(self, price: int, salt: str):
        result = self._run(functionName="getHashFromPrice", functionParams={"price":price, "salt":salt})
        return result

    

# ==============================================================================
# 
