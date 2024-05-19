// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/QueryResponse.sol";

error InvalidOwner();
error InvalidCaller();
error InvalidCalldata();
error InvalidWormholeAddress();
error InvalidForeignChainID();
error ObsoleteUpdate();
error StaleUpdate();
error UnexpectedResultLength();
error UnexpectedResultMismatch();

contract AdPlatform is QueryResponse {
    using BytesParsing for bytes;

    struct ChainImpressions {
        uint16 chainID;
        uint256 impressionsCount;
        uint256 campaignID;
        uint256 blockNum;
    }

    address private immutable owner;
    uint16 private immutable myChainID;
    mapping(uint16 => ChainImpressions) private impressions;
    uint16[] private foreignChainIDs;

    bytes4 GetImpressionsCountSig = bytes4(keccak256("getImpressionsCount()"));

    constructor(address _owner, address _wormhole, uint16 _myChainID) QueryResponse(_wormhole) {
        if (_owner == address(0)) revert InvalidOwner();
        if (_wormhole == address(0)) revert InvalidWormholeAddress();

        owner = _owner;
        myChainID = _myChainID;
        impressions[_myChainID] = ChainImpressions(_myChainID, 0, 0, 0);
    }

    function updateRegistration(uint16 _chainID) external onlyOwner {
        if (impressions[_chainID].chainID == 0) {
            foreignChainIDs.push(_chainID);
            impressions[_chainID] = ChainImpressions(_chainID, 0, 0, 0);
        }
    }

    function trackAdImpression(uint256 _campaignID) external {
        impressions[myChainID].impressionsCount++;
        impressions[myChainID].campaignID = _campaignID;
    }

    function getImpressionsCount() external view returns (uint256) {
        return impressions[myChainID].impressionsCount;
    }

    function getCampaignID() external view returns (uint256) {
        return impressions[myChainID].campaignID;
    }

    function updateImpressions(bytes memory response, IWormhole.Signature[] memory signatures) external {
        ParsedQueryResponse memory parsedResponse = parseAndVerifyQueryResponse(response, signatures);
        if (parsedResponse.responses.length != foreignChainIDs.length) revert UnexpectedResultLength();

        for (uint256 i = 0; i < foreignChainIDs.length; i++) {
            ChainImpressions storage foreignImpressions = impressions[parsedResponse.responses[i].chainId];
            if (foreignImpressions.chainID != foreignChainIDs[i]) revert InvalidForeignChainID();

            EthCallQueryResponse memory ethCallResponse = parseEthCallQueryResponse(parsedResponse.responses[i]);

            validateBlockNum(ethCallResponse.blockNum, foreignImpressions.blockNum);
            validateBlockTime(ethCallResponse.blockTime, block.timestamp - 300);

            address[] memory validAddresses = new address[](1);
            bytes4[] memory validFunctionSignatures = new bytes4[](1);
            validateMultipleEthCallData(ethCallResponse.result, validAddresses, validFunctionSignatures);

            foreignImpressions.blockNum = ethCallResponse.blockNum;
            foreignImpressions.impressionsCount = abi.decode(ethCallResponse.result[0].result, (uint256));
        }

        impressions[myChainID].impressionsCount++;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert InvalidCaller();
        _;
    }
}
