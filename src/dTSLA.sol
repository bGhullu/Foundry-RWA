//SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";

/*
 * @title dTSLA
 *@author Bijay Ghullu learning from Patrick Collins
 */

contract dTSLA is ConfirmedOwner, FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    enum MintOrRedeem {
        mint,
        redeem
    }

    struct dTslaRequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrReedem;
    }

    address constant SEPOLIA_FUNCTIONS_ROUTE =
        0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant DON_ID =
        hex"66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000";
    uint32 constant GAS_LIMIT = 300_000;
    uint64 immutable i_subId;
    string private s_mintSourceCode;

    mapping(bytes32 requestId => dTslaRequest request)
        private s_requestIdToRequest;

    constructor(
        string memory mintSourceCode,
        uint64 subId
    ) ConfirmedOwner(msg.sender) FunctionsClient(SEPOLIA_FUNCTIONS_ROUTE) {
        s_mintSourceCode = mintSourceCode;
        i_subId = subId;
    }

    // Send an HTTP Request to:
    // 1. See how much TSLA is bought
    // 2. If enough TSLA is in the alpaca account
    // mint dTSLA
    // 2 Transaction function
    function sendMintRequest(
        uint256 amount
    ) external onlyOwner returns (bytes32) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSourceCode);
        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            i_subId,
            GAS_LIMIT,
            DON_ID
        );
        s_requestIdToRequest[requestId] = dTslaRequest(
            amount,
            msg.sender,
            MintOrRedeem.mint
        );
        return requestId;
    }

    function _mintFulfillRequest() internal {}

    // @notice User send a request to sell TSLA for USDC (redemptionToken)
    // This will, have the chainlink function call our alpaca (bank) and
    // do the the following:
    // 1. Sell TSLA on the bokerage
    // 2. Buy USDC on the bokerage
    // 3. Send USDC to this contact for the user to withdraw

    function sendReedemRequest() external {}

    function _redeemFulFillRequest() internal {}
}
