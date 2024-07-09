//SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/*
 * @title dTSLA
 *@author Bijay Ghullu learning from Patrick Collins
 */

contract dTSLA is ConfirmedOwner, FunctionsClient, ERC20 {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    error dTSLA_NotEnoughCollateral();
    error dTSLA_DoesntMeetMinimumWithdrawlAmount();
    error dTSLA_TRNASFER_FAILED();

    enum MintOrRedeem {
        mint,
        redeem
    }

    struct dTslaRequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrReedem;
    }

    // Math constants
    uint256 constant PRECISION = 1e18;
    address constant SEPOLIA_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SEPOLIA_FUNCTIONS_ROUTE =
        0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    address constant SEPOLIA_USDC_PRICE_FEED =
        0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address constant SEPOLIA_TSLA_PRICE_FEED =
        0xc59E3633BAAC79493d908e63626716e204A45EdF; // This is actually LINK/USD priceFeed for demo purpose
    uint256 constant ADDITIONAL_FEED_PRECISION = 1e10;
    bytes32 constant DON_ID =
        hex"66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000";

    uint32 constant GAS_LIMIT = 300_000;
    uint64 immutable i_subId;
    uint256 private s_portfolioBalance;

    // If there is $200 of TSLA in the brokerage, we can mint AT MOST $100 of dTSLA
    uint256 constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    uint256 constant COLLATERAL_PRECISION = 100;
    uint256 constant MINIMUM_WITHDRAWL_AMOUNT = 100e18;
    string private s_mintSourceCode;
    string private s_redeemSourceCode;
    bytes32 private s_mostRecentRequestId;

    mapping(bytes32 requestId => dTslaRequest request)
        private s_requestIdToRequest;
    mapping(address user => uint256 pendingWithdrawlAmount)
        private s_userToWithdrawlAmount;
    uint8 donHostedSecretsSlotID = 0;
    uint64 donHostedSecretsVersion = 1712769962;

    constructor(
        string memory mintSourceCode,
        uint64 subId,
        string memory redeemSourceCode
    )
        ConfirmedOwner(msg.sender)
        FunctionsClient(SEPOLIA_FUNCTIONS_ROUTE)
        ERC20("dTSLA", "dTSLA")
    {
        s_mintSourceCode = mintSourceCode;
        i_subId = subId;
        s_redeemSourceCode = redeemSourceCode;
    }

    // Send an HTTP Request to:
    // 1. See how much TSLA is bought
    // 2. If enough TSLA is in the alpaca account mint dTSLA
    // 2 Transaction function
    function sendMintRequest(
        uint256 amount
    ) external onlyOwner returns (bytes32) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSourceCode);
        req.addDONHostedSecrets(
            donHostedSecretsSlotID,
            donHostedSecretsVersion
        );
        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            i_subId,
            GAS_LIMIT,
            DON_ID
        );
        s_mostRecentRequestId = requestId;
        s_requestIdToRequest[requestId] = dTslaRequest(
            amount,
            msg.sender,
            MintOrRedeem.mint
        );
        return requestId;
    }

    // Return the amount of TSLA value (in USD) is stored in our brokerage account
    // If we have enough TSLA token, mint the dTSLA
    function _mintFulfillRequest(
        bytes32 requestId,
        bytes memory response
    ) internal {
        uint256 amountOfTokensToMint = s_requestIdToRequest[requestId]
            .amountOfToken;
        s_portfolioBalance = uint256(bytes32(response));

        // If the TSLA collateral (how much TSLA we've bough)> dTSLA to mint -> mint
        // How much TSLA in $$$ do we have?
        // How much TSLA in $$$ are we minting?
        if (
            _getCollateralRatioAdjustedToTotalBalance(amountOfTokensToMint) >
            s_portfolioBalance
        ) {
            revert dTSLA_NotEnoughCollateral();
        }
        if (amountOfTokensToMint != 0) {
            _mint(
                s_requestIdToRequest[requestId].requester,
                amountOfTokensToMint
            );
        }
    }

    // @notice User send a request to sell TSLA for USDC (redemptionToken)
    // This will, have the chainlink function call our alpaca (bank) and
    // do the the following:
    // 1. Sell TSLA on the bokerage
    // 2. Buy USDC on the bokerage
    // 3. Send USDC to this contact for the user to withdraw

    function sendReedemRequest(uint256 amountdTsla) external {
        uint256 amountdTslaInUsdc = getUsdcValueOfUsd(
            getUsdValueOfTsla(amountdTsla)
        );
        if (amountdTslaInUsdc < MINIMUM_WITHDRAWL_AMOUNT) {
            revert dTSLA_DoesntMeetMinimumWithdrawlAmount();
        }
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_redeemSourceCode);
        string[] memory args = new string[](2);
        args[0] = amountdTsla.toString();
        args[1] = amountdTslaInUsdc.toString();
        req.setArgs(args);
        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            i_subId,
            GAS_LIMIT,
            DON_ID
        );
        s_requestIdToRequest[requestId] = dTslaRequest(
            amountdTsla,
            msg.sender,
            MintOrRedeem.redeem
        );
        s_mostRecentRequestId = requestId;
        _burn(msg.sender, amountdTsla);
    }

    function _redeemFulFillRequest(
        bytes32 requestId,
        bytes memory response
    ) internal {
        //assume for now this has 18 decimals
        uint256 usdcAmount = uint256(bytes32(response));
        if (usdcAmount == 0) {
            uint256 amountOfdTslaBurned = s_requestIdToRequest[requestId]
                .amountOfToken;
            _mint(
                s_requestIdToRequest[requestId].requester,
                amountOfdTslaBurned
            );
            return;
        }
        s_userToWithdrawlAmount[
            s_requestIdToRequest[requestId].requester
        ] += usdcAmount;
    }

    function withdraw() external {
        uint256 amountToWithdraw = s_userToWithdrawlAmount[msg.sender];
        s_userToWithdrawlAmount[msg.sender] = 0;
        bool succcess = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
            .transfer(msg.sender, amountToWithdraw);
        if (!succcess) {
            revert dTSLA_TRNASFER_FAILED();
        }
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory /*err*/
    ) internal override {
        if (s_requestIdToRequest[requestId].mintOrReedem == MintOrRedeem.mint) {
            _mintFulfillRequest(requestId, response);
        } else {
            _redeemFulFillRequest(requestId, response);
        }
    }

    function finishMint() external onlyOwner {
        uint256 amountOfTokensToMint = s_requestIdToRequest[
            s_mostRecentRequestId
        ].amountOfToken;
        _mint(
            s_requestIdToRequest[s_mostRecentRequestId].requester,
            amountOfTokensToMint
        );
    }

    function _getCollateralRatioAdjustedToTotalBalance(
        uint256 amountOfTokensToMint
    ) internal view returns (uint256) {
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(
            amountOfTokensToMint
        );
        return ((calculatedNewTotalValue * COLLATERAL_RATIO) /
            COLLATERAL_PRECISION);
    }

    // The new expected total value in USD of all the dTSLA tokens combined
    function getCalculatedNewTotalValue(
        uint256 addedNumberOfTokens
    ) internal view returns (uint256) {
        // 10 dTSLA tokens + 5 dTSLA tokens = 15 dTSLA tokens * TSLA price(100) = 1500
        return
            ((totalSupply() + addedNumberOfTokens) * getTslaPrice()) /
            PRECISION;
    }

    function getUsdcValueOfUsd(
        uint256 usdAmount
    ) public view returns (uint256) {
        return (getUsdcPrice() * usdAmount) / PRECISION;
    }

    function getUsdValueOfTsla(
        uint256 tslaAmount
    ) public view returns (uint256) {
        return (tslaAmount * getTslaPrice()) / PRECISION;
    }

    function getTslaPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            SEPOLIA_TSLA_PRICE_FEED
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION; // To have 18 decimals
    }

    function getUsdcPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            SEPOLIA_USDC_PRICE_FEED
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION; // To have 18 decimals
    }

    function getRequest(
        bytes32 requestId
    ) public view returns (dTslaRequest memory) {
        return s_requestIdToRequest[requestId];
    }

    function getPendingWithdrawlAmount(
        address user
    ) public view returns (uint256) {
        return s_userToWithdrawlAmount[user];
    }

    function getPortfolioBalance() public view returns (uint256) {
        return s_portfolioBalance;
    }

    function getSubId() public view returns (uint64) {
        return i_subId;
    }

    function getMintSouceCode() public view returns (string memory) {
        return s_mintSourceCode;
    }

    function getRedeemSourceCode() public view returns (string memory) {
        return s_redeemSourceCode;
    }

    function getCollateralRatio() public pure returns (uint256) {
        return COLLATERAL_RATIO;
    }

    function getCollateralPrecision() public pure returns (uint256) {
        return COLLATERAL_PRECISION;
    }
}
