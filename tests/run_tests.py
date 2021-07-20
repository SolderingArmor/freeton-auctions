#!/usr/bin/env python3

# ==============================================================================
# 
import freeton_utils
from   freeton_utils import *
import binascii
import unittest
import time
import sys
from   pathlib import Path
from   pprint import pprint
from   contract_AuctionManagerDnsRecord import AuctionManagerDnsRecord
from   contract_AuctionDnsRecord        import AuctionDnsRecord
from   contract_DnsRecordTEST           import DnsRecordTEST

#TON  = 1000000000
#DIME =  100000000
SERVER_ADDRESS = "https://net.ton.dev"

# ==============================================================================
#
def getClient():
    return TonClient(config=ClientConfig(network=NetworkConfig(server_address=SERVER_ADDRESS)))

# ==============================================================================
# 
# Parse arguments and then clear them because UnitTest will @#$~!
for _, arg in enumerate(sys.argv[1:]):
    if arg == "--disable-giver":
        
        freeton_utils.USE_GIVER = False
        sys.argv.remove(arg)

    if arg == "--throw":
        
        freeton_utils.THROW = True
        sys.argv.remove(arg)

    if arg.startswith("http"):
        
        SERVER_ADDRESS = arg
        sys.argv.remove(arg)

    if arg.startswith("--msig-giver"):
        
        freeton_utils.MSIG_GIVER = arg[13:]
        sys.argv.remove(arg)

# ==============================================================================
# EXIT CODE FOR SINGLE-MESSAGE OPERATIONS
# we know we have only 1 internal message, that's why this wrapper has no filters
def _getAbiArray():
    return ["../bin/DnsRecord.abi.json", "../bin/AuctionBid.abi.json", "../bin/AuctionManagerDnsRecord.abi.json", "../bin/AuctionDnsRecord.abi.json", "../bin/SetcodeMultisigWallet.abi.json"]

def _getExitCode(msgIdArray):
    abiArray     = _getAbiArray()
    msgArray     = unwrapMessages(getClient(), msgIdArray, abiArray)
    if msgArray != "":
        realExitCode = msgArray[0]["TX_DETAILS"]["compute"]["exit_code"]
    else:
        realExitCode = -1
    return realExitCode   

def readBinaryFile(fileName):
    with open(fileName, 'rb') as f:
        contents = f.read()
    #return(binascii.hexlify(contents).hex(), Path(fileName).stem, Path(fileName).suffix)
    return(contents.hex(), Path(fileName).stem, Path(fileName).suffix)

def chunkstring(string, length):
    return list(string[0+i:length+i] for i in range(0, len(string), length))

# ==============================================================================
# 
class Test_01_CancelDnsAuction(unittest.TestCase):

    msig    = SetcodeMultisig(tonClient=getClient())
    msig2   = SetcodeMultisig(tonClient=getClient())
    domain  = DnsRecordTEST(tonClient=getClient(), name="kek")
    dtNow   = getNowTimestamp()
    
    auction = AuctionDnsRecord(
        tonClient     = getClient(), 
        # statics
        sellerAddress = msig.ADDRESS, 
        buyerAddress  = msig2.ADDRESS,
        assetAddress  = domain.ADDRESS, 
        auctionType   = 4, # PRIVATE_BUY 
        dtStart       = dtNow + 1,
        # constructor
        escrowAddress = msig.ADDRESS, 
        escrowPercent = 500,
        feeValue      = DIME*5,
        minBid        = TON,
        minPriceStep  = TON, 
        buyNowPrice   = TON*6, 
        dtEnd         = dtNow+70,
        dtRevealEnd   = 0, # it is not blind auction
        dutchCycle    = 0) # it is not dutch auction

    manager = AuctionManagerDnsRecord(tonClient=getClient(), ownerAddress=msig.ADDRESS, bidCode=getCodeFromTvc(auction.TVC_BID), auctionCode=getCodeFromTvc(auction.TVC))
    
    def test_0(self):
        print("\n\n----------------------------------------------------------------------")
        print("Running:", self.__class__.__name__)

    # 1. Giver
    def test_1(self):
        giverGive(getClient(), self.msig.ADDRESS,    TON * 10)
        giverGive(getClient(), self.msig2.ADDRESS,   TON * 20)
        giverGive(getClient(), self.manager.ADDRESS, TON * 1)
        giverGive(getClient(), self.domain.ADDRESS,  TON * 1)
        giverGive(getClient(), self.auction.ADDRESS, TON * 1)

        #print(self.auction.ADDRESS)

    # 2. Deploy multisig
    def test_2(self):
        result = self.msig.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.domain.deploy(ownerAddress=self.msig.ADDRESS)
        self.assertEqual(result[1]["errorCode"], 0)

    # 3. Deploy something else
    def test_3(self):
        result = self.manager.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        
    # 4. Get info
    def test_4(self):

        result = self.manager.createAuctionDnsRecord(msig=self.msig, value=TON, 
            sellerAddress = self.msig.ADDRESS, 
            buyerAddress  = self.msig2.ADDRESS,
            assetAddress  = self.domain.ADDRESS, 
            auctionType   = 4, # PRIVATE_BUY 
            dtStart       = self.dtNow + 1,
            # constructor
            feeValue      = DIME*5,
            minBid        = TON,
            minPriceStep  = TON, 
            buyNowPrice   = TON*6, 
            dtEnd         = self.dtNow+70,
            dtRevealEnd   = 0, # it is not blind auction
            dutchCycle    = 0) # it is not dutch auction

        result = self.domain.callFromMultisig(msig=self.msig, functionName="changeOwner", functionParams={"newOwnerAddress": self.auction.ADDRESS}, value=100000000, flags=1)

        result = self.auction.receiveAsset(msig=self.msig, value=100000000)
        msgArray = unwrapMessages(getClient(), result[0].transaction["out_msgs"], _getAbiArray())

        # try to finalize when it's not the time to do that
        result = self.auction.finalize(msig=self.msig2, value=TON)
        exitCode = _getExitCode(result[0].transaction["out_msgs"])
        self.assertEqual(exitCode, 203) # ERROR_AUCTION_IN_PROCESS

        result = self.auction.cancelAuction(msig=self.msig, value=TON)

        result = self.auction.finalize(msig=self.msig2, value=TON)
        result = self.auction.finalize(msig=self.msig2, value=TON)
        msgArray = unwrapMessages(getClient(), result[0].transaction["out_msgs"], _getAbiArray())
        
        result = self.domain.run(functionName="getWhois", functionParams={})
        self.assertEqual(result["ownerAddress"], self.msig.ADDRESS)

    # 5. Cleanup
    def test_5(self):
        result = self.msig.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

        result = self.domain.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

# ==============================================================================
# 
class Test_02_DeployDnsAuctionPrivate(unittest.TestCase):

    msig    = SetcodeMultisig(tonClient=getClient())
    msig2   = SetcodeMultisig(tonClient=getClient())
    domain  = DnsRecordTEST(tonClient=getClient(), name="kek")
    dtNow   = getNowTimestamp()
    
    auction = AuctionDnsRecord(
        tonClient     = getClient(), 
        # statics
        sellerAddress = msig.ADDRESS, 
        buyerAddress  = msig2.ADDRESS,
        assetAddress  = domain.ADDRESS, 
        auctionType   = 4, # PRIVATE_BUY 
        dtStart       = dtNow + 1,
        # constructor
        escrowAddress = msig.ADDRESS, 
        escrowPercent = 500,
        feeValue      = DIME*5,
        minBid        = TON,
        minPriceStep  = TON, 
        buyNowPrice   = TON*6, 
        dtEnd         = dtNow+70,
        dtRevealEnd   = 0, # it is not blind auction
        dutchCycle    = 0) # it is not dutch auction

    manager = AuctionManagerDnsRecord(tonClient=getClient(), ownerAddress=msig.ADDRESS, bidCode=getCodeFromTvc(auction.TVC_BID), auctionCode=getCodeFromTvc(auction.TVC))
    
    def test_0(self):
        print("\n\n----------------------------------------------------------------------")
        print("Running:", self.__class__.__name__)

    # 1. Giver
    def test_1(self):
        giverGive(getClient(), self.msig.ADDRESS,    TON * 10)
        giverGive(getClient(), self.msig2.ADDRESS,   TON * 20)
        giverGive(getClient(), self.manager.ADDRESS, TON * 1)
        giverGive(getClient(), self.domain.ADDRESS,  TON * 1)
        giverGive(getClient(), self.auction.ADDRESS, TON * 1)

        #print(self.auction.ADDRESS)

    # 2. Deploy multisig
    def test_2(self):
        result = self.msig.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.domain.deploy(ownerAddress=self.msig.ADDRESS)
        self.assertEqual(result[1]["errorCode"], 0)

    # 3. Deploy something else
    def test_3(self):
        result = self.manager.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        
    # 4. Get info
    def test_4(self):

        result = self.manager.createAuctionDnsRecord(msig=self.msig, value=TON, 
            sellerAddress = self.msig.ADDRESS, 
            buyerAddress  = self.msig2.ADDRESS,
            assetAddress  = self.domain.ADDRESS, 
            auctionType   = 4, # PRIVATE_BUY 
            dtStart       = self.dtNow + 1,
            # constructor
            feeValue      = DIME*5,
            minBid        = TON,
            minPriceStep  = TON, 
            buyNowPrice   = TON*6, 
            dtEnd         = self.dtNow+70,
            dtRevealEnd   = 0, # it is not blind auction
            dutchCycle    = 0) # it is not dutch auction
        
        result = self.domain.callFromMultisig(msig=self.msig, functionName="changeOwner", functionParams={"newOwnerAddress": self.auction.ADDRESS}, value=100000000, flags=1)

        result = self.auction.receiveAsset(msig=self.msig,  value=100000000)
        result = self.auction.bid         (msig=self.msig2, value=TON*7)

        result = self.auction.finalize(msig=self.msig2, value=TON)
        result = self.auction.finalize(msig=self.msig2, value=TON)
        msgArray = unwrapMessages(getClient(), result[0].transaction["out_msgs"], _getAbiArray())

        result = self.domain.run(functionName="getWhois", functionParams={})
        self.assertEqual(result["ownerAddress"], self.msig2.ADDRESS)

    # 5. Cleanup
    def test_5(self):
        result = self.msig.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

        result = self.domain.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

# ==============================================================================
# 
class Test_03_DeployDnsAuctionPublic(unittest.TestCase):

    msig    = SetcodeMultisig(tonClient=getClient())
    msig2   = SetcodeMultisig(tonClient=getClient())
    domain  = DnsRecordTEST(tonClient=getClient(), name="kek")
    dtNow   = getNowTimestamp()
    
    auction = AuctionDnsRecord(
        tonClient     = getClient(), 
        # statics
        sellerAddress = msig.ADDRESS, 
        buyerAddress  = ZERO_ADDRESS,
        assetAddress  = domain.ADDRESS, 
        auctionType   = 3, # PUBLIC_BUY 
        dtStart       = dtNow + 1,
        # constructor
        escrowAddress = msig.ADDRESS, 
        escrowPercent = 500,
        feeValue      = DIME*5,
        minBid        = TON,
        minPriceStep  = TON, 
        buyNowPrice   = TON*6, 
        dtEnd         = dtNow+70,
        dtRevealEnd   = 0, # it is not blind auction
        dutchCycle    = 0) # it is not dutch auction

    manager = AuctionManagerDnsRecord(tonClient=getClient(), ownerAddress=msig.ADDRESS, bidCode=getCodeFromTvc(auction.TVC_BID), auctionCode=getCodeFromTvc(auction.TVC))
    
    def test_0(self):
        print("\n\n----------------------------------------------------------------------")
        print("Running:", self.__class__.__name__)

    # 1. Giver
    def test_1(self):
        giverGive(getClient(), self.msig.ADDRESS,    TON * 10)
        giverGive(getClient(), self.msig2.ADDRESS,   TON * 20)
        giverGive(getClient(), self.manager.ADDRESS, TON * 1)
        giverGive(getClient(), self.domain.ADDRESS,  TON * 1)
        giverGive(getClient(), self.auction.ADDRESS, TON * 1)

        #print(self.auction.ADDRESS)

    # 2. Deploy multisig
    def test_2(self):
        result = self.msig.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.domain.deploy(ownerAddress=self.msig.ADDRESS)
        self.assertEqual(result[1]["errorCode"], 0)

    # 3. Deploy something else
    def test_3(self):
        result = self.manager.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        
    # 4. Get info
    def test_4(self):

        result = self.manager.createAuctionDnsRecord(msig=self.msig, value=TON, 
            sellerAddress = self.msig.ADDRESS, 
            buyerAddress  = ZERO_ADDRESS,
            assetAddress  = self.domain.ADDRESS, 
            auctionType   = 3, # PUBLIC_BUY 
            dtStart       = self.dtNow + 1,
            # constructor
            feeValue      = DIME*5,
            minBid        = TON,
            minPriceStep  = TON, 
            buyNowPrice   = TON*6, 
            dtEnd         = self.dtNow+70,
            dtRevealEnd   = 0, # it is not blind auction
            dutchCycle    = 0) # it is not dutch auction
        
        result = self.domain.callFromMultisig(msig=self.msig, functionName="changeOwner", functionParams={"newOwnerAddress": self.auction.ADDRESS}, value=100000000, flags=1)

        result = self.auction.receiveAsset(msig=self.msig,  value=100000000)
        result = self.auction.bid         (msig=self.msig2, value=TON*7)

        result = self.auction.finalize(msig=self.msig2, value=TON)
        result = self.auction.finalize(msig=self.msig2, value=TON)
        msgArray = unwrapMessages(getClient(), result[0].transaction["out_msgs"], _getAbiArray())

        result = self.domain.run(functionName="getWhois", functionParams={})
        self.assertEqual(result["ownerAddress"], self.msig2.ADDRESS)

    # 5. Cleanup
    def test_5(self):
        result = self.msig.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

        result = self.domain.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

# ==============================================================================
# 
class Test_04_DeployDnsAuctionEnglishForward(unittest.TestCase):

    msig    = SetcodeMultisig(tonClient=getClient())
    msig2   = SetcodeMultisig(tonClient=getClient())
    msig3   = SetcodeMultisig(tonClient=getClient())
    msig4   = SetcodeMultisig(tonClient=getClient())
    msig5   = SetcodeMultisig(tonClient=getClient())
    domain  = DnsRecordTEST(tonClient=getClient(), name="kek")
    dtNow   = getNowTimestamp()
    
    auction = AuctionDnsRecord(
        tonClient     = getClient(), 
        # statics
        sellerAddress = msig.ADDRESS, 
        buyerAddress  = ZERO_ADDRESS,
        assetAddress  = domain.ADDRESS, 
        auctionType   = 0, # ENGLISH_FORWARD 
        dtStart       = dtNow + 1,
        # constructor
        escrowAddress = msig.ADDRESS, 
        escrowPercent = 500,
        feeValue      = DIME*5,
        minBid        = TON,
        minPriceStep  = TON, 
        buyNowPrice   = TON*6, 
        dtEnd         = dtNow+170,
        dtRevealEnd   = 0, # it is not blind auction
        dutchCycle    = 0) # it is not dutch auction

    manager = AuctionManagerDnsRecord(tonClient=getClient(), ownerAddress=msig.ADDRESS, bidCode=getCodeFromTvc(auction.TVC_BID), auctionCode=getCodeFromTvc(auction.TVC))
    
    def test_0(self):
        print("\n\n----------------------------------------------------------------------")
        print("Running:", self.__class__.__name__)

    # 1. Giver
    def test_1(self):
        giverGive(getClient(), self.msig.ADDRESS,    TON * 10)
        giverGive(getClient(), self.msig2.ADDRESS,   TON * 10)
        giverGive(getClient(), self.msig3.ADDRESS,   TON * 10)
        giverGive(getClient(), self.msig4.ADDRESS,   TON * 10)
        giverGive(getClient(), self.msig5.ADDRESS,   TON * 10)
        giverGive(getClient(), self.manager.ADDRESS, TON * 1)
        giverGive(getClient(), self.domain.ADDRESS,  TON * 1)
        giverGive(getClient(), self.auction.ADDRESS, TON * 1)

    # 2. Deploy multisig
    def test_2(self):
        result = self.msig.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig3.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig4.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig5.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.domain.deploy(ownerAddress=self.msig.ADDRESS)
        self.assertEqual(result[1]["errorCode"], 0)

    # 3. Deploy something else
    def test_3(self):
        result = self.manager.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        
    # 4. Get info
    def test_4(self):

        result = self.manager.createAuctionDnsRecord(msig=self.msig, value=TON, 
            sellerAddress = self.msig.ADDRESS, 
            buyerAddress  = ZERO_ADDRESS,
            assetAddress  = self.domain.ADDRESS, 
            auctionType   = 0, # ENGLISH_FORWARD 
            dtStart       = self.dtNow + 1,
            # constructor
            feeValue      = DIME*5,
            minBid        = TON,
            minPriceStep  = TON, 
            buyNowPrice   = TON*6, 
            dtEnd         = self.dtNow+170,
            dtRevealEnd   = 0, # it is not blind auction
            dutchCycle    = 0) # it is not dutch auction
        
        result = self.domain.callFromMultisig(msig=self.msig, functionName="changeOwner", functionParams={"newOwnerAddress": self.auction.ADDRESS}, value=100000000, flags=1)

        result = self.auction.receiveAsset(msig=self.msig,  value=100000000)

        # starting a bid fight
        result = self.auction.bid(msig=self.msig2, value=TON*2)
        result = self.auction.getInfo()
        self.assertEqual(result["currentBuyer"], self.msig2.ADDRESS)

        result = self.auction.bid(msig=self.msig3, value=TON*3)
        result = self.auction.getInfo()
        self.assertEqual(result["currentBuyer"], self.msig3.ADDRESS)

        result = self.auction.bid(msig=self.msig4, value=TON*4)
        result = self.auction.getInfo()
        self.assertEqual(result["currentBuyer"], self.msig4.ADDRESS)

        result = self.auction.bid(msig=self.msig5, value=TON*5)
        result = self.auction.getInfo()
        self.assertEqual(result["currentBuyer"], self.msig5.ADDRESS)

        result = self.auction.bid(msig=self.msig3, value=TON*7)
        result = self.auction.getInfo()
        self.assertEqual(result["currentBuyer"], self.msig3.ADDRESS)

        # ================================
        # 
        result = self.auction.finalize(msig=self.msig3, value=TON)
        result = self.auction.finalize(msig=self.msig3, value=TON)
        msgArray = unwrapMessages(getClient(), result[0].transaction["out_msgs"], _getAbiArray())

        result = self.domain.run(functionName="getWhois", functionParams={})
        self.assertEqual(result["ownerAddress"], self.msig3.ADDRESS)

    # 5. Cleanup
    def test_5(self):
        result = self.msig.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig3.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig4.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig5.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

        result = self.domain.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

# ==============================================================================
# 
class Test_05_DeployDnsAuctionDutchForward(unittest.TestCase):

    msig    = SetcodeMultisig(tonClient=getClient())
    msig2   = SetcodeMultisig(tonClient=getClient())
    domain  = DnsRecordTEST(tonClient=getClient(), name="kek")
    dtNow   = getNowTimestamp()
    
    auction = AuctionDnsRecord(
        tonClient     = getClient(), 
        # statics
        sellerAddress = msig.ADDRESS, 
        buyerAddress  = ZERO_ADDRESS,
        assetAddress  = domain.ADDRESS, 
        auctionType   = 2, # DUTCH_FORWARD 
        dtStart       = dtNow + 1,
        # constructor
        escrowAddress = msig.ADDRESS, 
        escrowPercent = 500,
        feeValue      = DIME*5,
        minBid        = TON*10,
        minPriceStep  = DIME, 
        buyNowPrice   = TON, 
        dtEnd         = dtNow+170,
        dtRevealEnd   = 0, # it is not blind auction
        dutchCycle    = 2)

    manager = AuctionManagerDnsRecord(tonClient=getClient(), ownerAddress=msig.ADDRESS, bidCode=getCodeFromTvc(auction.TVC_BID), auctionCode=getCodeFromTvc(auction.TVC))
    
    def test_0(self):
        print("\n\n----------------------------------------------------------------------")
        print("Running:", self.__class__.__name__)

    # 1. Giver
    def test_1(self):
        giverGive(getClient(), self.msig.ADDRESS,    TON * 10)
        giverGive(getClient(), self.msig2.ADDRESS,   TON * 20)
        giverGive(getClient(), self.manager.ADDRESS, TON * 1)
        giverGive(getClient(), self.domain.ADDRESS,  TON * 1)
        giverGive(getClient(), self.auction.ADDRESS, TON * 1)

        #print(self.auction.ADDRESS)

    # 2. Deploy multisig
    def test_2(self):
        result = self.msig.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.domain.deploy(ownerAddress=self.msig.ADDRESS)
        self.assertEqual(result[1]["errorCode"], 0)

    # 3. Deploy something else
    def test_3(self):
        result = self.manager.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        
    # 4. Get info
    def test_4(self):

        result = self.manager.createAuctionDnsRecord(msig=self.msig, value=TON, 
            sellerAddress = self.msig.ADDRESS, 
            buyerAddress  = ZERO_ADDRESS,
            assetAddress  = self.domain.ADDRESS, 
            auctionType   = 2, # DUTCH_FORWARD 
            dtStart       = self.dtNow + 1,
            # constructor
            feeValue      = DIME*5,
            minBid        = TON*10,
            minPriceStep  = DIME, 
            buyNowPrice   = TON, 
            dtEnd         = self.dtNow+170,
            dtRevealEnd   = 0, # it is not blind auction
            dutchCycle    = 2)
        
        result = self.domain.callFromMultisig(msig=self.msig, functionName="changeOwner", functionParams={"newOwnerAddress": self.auction.ADDRESS}, value=100000000, flags=1)

        result = self.auction.receiveAsset(msig=self.msig,  value=100000000)

        time.sleep(5)

        result = self.auction.bid     (msig=self.msig2, value=TON*11)
        result = self.auction.finalize(msig=self.msig2, value=TON)
        result = self.auction.finalize(msig=self.msig2, value=TON)
        msgArray = unwrapMessages(getClient(), result[0].transaction["out_msgs"], _getAbiArray())

        result = self.domain.run(functionName="getWhois", functionParams={})
        self.assertEqual(result["ownerAddress"], self.msig2.ADDRESS)

    # 5. Cleanup
    def test_5(self):
        result = self.msig.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

        result = self.domain.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

# ==============================================================================
# 
class Test_06_DeployDnsAuctionEnglishBlind(unittest.TestCase):

    msig    = SetcodeMultisig(tonClient=getClient())
    msig2   = SetcodeMultisig(tonClient=getClient())
    domain  = DnsRecordTEST(tonClient=getClient(), name="kek")
    dtNow   = getNowTimestamp()
    
    auction = AuctionDnsRecord(
        tonClient     = getClient(), 
        # statics
        sellerAddress = msig.ADDRESS, 
        buyerAddress  = ZERO_ADDRESS,
        assetAddress  = domain.ADDRESS, 
        auctionType   = 1, # ENGLISH_BLIND 
        dtStart       = dtNow + 1,
        # constructor
        escrowAddress = msig.ADDRESS, 
        escrowPercent = 500,
        feeValue      = DIME*5,
        minBid        = TON,
        minPriceStep  = 0, 
        buyNowPrice   = 0, 
        dtEnd         = dtNow+20,
        dtRevealEnd   = dtNow+40,
        dutchCycle    = 0)

    manager = AuctionManagerDnsRecord(tonClient=getClient(), ownerAddress=msig.ADDRESS, bidCode=getCodeFromTvc(auction.TVC_BID), auctionCode=getCodeFromTvc(auction.TVC))
    
    def test_0(self):
        print("\n\n----------------------------------------------------------------------")
        print("Running:", self.__class__.__name__)

    # 1. Giver
    def test_1(self):
        giverGive(getClient(), self.msig.ADDRESS,    TON * 10)
        giverGive(getClient(), self.msig2.ADDRESS,   TON * 20)
        giverGive(getClient(), self.manager.ADDRESS, TON * 1)
        giverGive(getClient(), self.domain.ADDRESS,  TON * 1)
        giverGive(getClient(), self.auction.ADDRESS, TON * 1)

        #print(self.auction.ADDRESS)

    # 2. Deploy multisig
    def test_2(self):
        result = self.msig.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.domain.deploy(ownerAddress=self.msig.ADDRESS)
        self.assertEqual(result[1]["errorCode"], 0)

    # 3. Deploy something else
    def test_3(self):
        result = self.manager.deploy()
        self.assertEqual(result[1]["errorCode"], 0)
        
    # 4. Get info
    def test_4(self):

        price1 = TON*2
        salt1  = "123424534654"
        hash1  = self.manager.getHashFromPrice(price=price1, salt=salt1)

        price2 = TON*3
        salt2  = "12389053544654"
        hash2  = self.manager.getHashFromPrice(price=price2, salt=salt2)
        
        result = self.manager.createAuctionDnsRecord(msig=self.msig, value=TON, 
            sellerAddress = self.msig.ADDRESS, 
            buyerAddress  = ZERO_ADDRESS,
            assetAddress  = self.domain.ADDRESS, 
            auctionType   = 1, # ENGLISH_BLIND 
            dtStart       = self.dtNow + 1,
            # constructor
            feeValue      = DIME*5,
            minBid        = TON,
            minPriceStep  = 0, 
            buyNowPrice   = 0, 
            dtEnd         = self.dtNow+20,
            dtRevealEnd   = self.dtNow+40,
            dutchCycle    = 0)
        
        result = self.domain.callFromMultisig(msig=self.msig, functionName="changeOwner", functionParams={"newOwnerAddress": self.auction.ADDRESS}, value=100000000, flags=1)
        result = self.auction.receiveAsset(msig=self.msig, value=100000000)

        result = self.auction.bidBlind(msig=self.msig,  value=TON, priceHash=str(hash1))
        result = self.auction.bidBlind(msig=self.msig2, value=TON, priceHash=str(hash2))
        #msgArray = unwrapMessages(getClient(), result[0].transaction["out_msgs"], _getAbiArray())
        #pprint(msgArray)
        
        time.sleep(15)

        result = self.auction.revealBidBlind(msig=self.msig,  value=TON*4, price=price1, salt=salt1)
        result = self.auction.revealBidBlind(msig=self.msig2, value=TON*5, price=price2, salt=salt2)
        #msgArray = unwrapMessages(getClient(), result[0].transaction["out_msgs"], _getAbiArray())
        #pprint(msgArray)

        time.sleep(20)

        result = self.auction.finalize(msig=self.msig2, value=TON)
        result = self.auction.finalize(msig=self.msig2, value=TON)
        msgArray = unwrapMessages(getClient(), result[0].transaction["out_msgs"], _getAbiArray())
        
        result = self.domain.run(functionName="getWhois", functionParams={})
        self.assertEqual(result["ownerAddress"], self.msig2.ADDRESS)

    # 5. Cleanup
    def test_5(self):
        result = self.msig.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)
        result = self.msig2.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

        result = self.domain.destroy(addressDest = freeton_utils.giverGetAddress())
        self.assertEqual(result[1]["errorCode"], 0)

# ==============================================================================
# 
unittest.main()
