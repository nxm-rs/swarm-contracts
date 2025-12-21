// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import "./interfaces/IPostageStamp.sol";

/**
 * @title PriceOracle contract.
 * @author The Swarm Authors.
 * @dev The price oracle contract emits a price feed using events.
 */

contract PriceOracle is OwnableRoles {
    // ----------------------------- Role Constants ------------------------------

    // Role allowed to update price
    uint256 public constant PRICE_UPDATER_ROLE = 1 << 0;

    // ----------------------------- State variables ------------------------------

    // The address of the linked PostageStamp contract
    IPostageStamp public postageStamp;

    uint16 targetRedundancy = 4;
    uint16 maxConsideredExtraRedundancy = 4;

    // When the contract is paused, price changes are not effective
    bool public isPaused = false;

    // The number of the last round price adjusting happend
    uint64 public lastAdjustedRound;

    // The minimum price allowed
    uint32 public minimumPriceUpscaled = 24_000 << 10; // we upscale it by 2^10

    // The priceBase to modulate the price
    uint32 public priceBase = 1_048_576;

    uint64 public currentPriceUpScaled = minimumPriceUpscaled;

    // Constants used to modulate the price, see below usage
    uint32[9] public changeRate = [
        1_049_417, 1_049_206, 1_048_996, 1_048_786, 1_048_576, 1_048_366, 1_048_156, 1_047_946, 1_047_736
    ];

    // The length of a round in blocks.
    uint8 private constant ROUND_LENGTH = 152;

    // ----------------------------- Events ------------------------------

    /**
     *@dev Emitted on every price update.
     */
    event PriceUpdate(uint256 price);
    event StampPriceUpdateFailed(uint256 attemptedPrice);

    // ----------------------------- Custom Errors ------------------------------
    error CallerNotAdmin(); // Caller is not the admin
    error CallerNotPriceUpdater(); // Caller is not a price updater
    error PriceAlreadyAdjusted(); // Price already adjusted in this round
    error UnexpectedZero(); // Redundancy needs to be higher then 0

    // ----------------------------- CONSTRUCTOR ------------------------------

    constructor(address _postageStamp) {
        _initializeOwner(msg.sender);
        postageStamp = IPostageStamp(_postageStamp);
        lastAdjustedRound = currentRound();
        emit PriceUpdate(currentPrice());
    }

    ////////////////////////////////////////
    //            STATE SETTING           //
    ////////////////////////////////////////

    /**
     * @notice Manually set the price.
     * @dev Can only be called by the owner.
     * @param _price The new price.
     */
    function setPrice(uint32 _price) external onlyOwner returns (bool) {
        uint64 _currentPriceUpScaled = _price << 10;
        uint64 _minimumPriceUpscaled = minimumPriceUpscaled;

        // Enforce minimum price
        if (_currentPriceUpScaled < _minimumPriceUpscaled) {
            _currentPriceUpScaled = _minimumPriceUpscaled;
        }
        currentPriceUpScaled = _currentPriceUpScaled;

        // Check if the setting of price in postagestamp succeded
        (bool success,) =
            address(postageStamp).call(abi.encodeWithSignature("setPrice(uint256)", uint256(currentPrice())));
        if (!success) {
            emit StampPriceUpdateFailed(currentPrice());
            return false;
        }
        emit PriceUpdate(currentPrice());
        return true;
    }

    function adjustPrice(uint16 redundancy) external onlyRoles(PRICE_UPDATER_ROLE) returns (bool) {
        if (isPaused == false) {
            uint16 usedRedundancy = redundancy;
            uint64 currentRoundNumber = currentRound();

            // Price can only be adjusted once per round
            if (currentRoundNumber <= lastAdjustedRound) {
                revert PriceAlreadyAdjusted();
            }
            // Redundancy may not be zero
            if (redundancy == 0) {
                revert UnexpectedZero();
            }

            // Enforce maximum considered extra redundancy
            uint16 maxConsideredRedundancy = targetRedundancy + maxConsideredExtraRedundancy;
            if (redundancy > maxConsideredRedundancy) {
                usedRedundancy = maxConsideredRedundancy;
            }

            uint64 _currentPriceUpScaled = currentPriceUpScaled;
            uint64 _minimumPriceUpscaled = minimumPriceUpscaled;
            uint32 _priceBase = priceBase;

            // Set the number of rounds that were skipped, we substract 1 as lastAdjustedRound is set below and default result is 1
            uint64 skippedRounds = currentRoundNumber - lastAdjustedRound - 1;

            // We first apply the increase/decrease rate for the current round
            uint32 _changeRate = changeRate[usedRedundancy];
            _currentPriceUpScaled = (_changeRate * _currentPriceUpScaled) / _priceBase;

            // If previous rounds were skipped, use MAX price increase for the previous rounds
            if (skippedRounds > 0) {
                _changeRate = changeRate[0];
                for (uint64 i = 0; i < skippedRounds; i++) {
                    _currentPriceUpScaled = (_changeRate * _currentPriceUpScaled) / _priceBase;
                }
            }

            // Enforce minimum price
            if (_currentPriceUpScaled < _minimumPriceUpscaled) {
                _currentPriceUpScaled = _minimumPriceUpscaled;
            }

            currentPriceUpScaled = _currentPriceUpScaled;
            lastAdjustedRound = currentRoundNumber;

            // Check if the price set in postagestamp succeded
            (bool success,) =
                address(postageStamp).call(abi.encodeWithSignature("setPrice(uint256)", uint256(currentPrice())));
            if (!success) {
                emit StampPriceUpdateFailed(currentPrice());
                return false;
            }
            emit PriceUpdate(currentPrice());
            return true;
        }
        return false;
    }

    function pause() external onlyOwner {
        isPaused = true;
    }

    function unPause() external onlyOwner {
        isPaused = false;
    }

    ////////////////////////////////////////
    //            STATE READING           //
    ////////////////////////////////////////

    /**
     * @notice Return the number of the current round.
     */
    function currentRound() public view returns (uint64) {
        // We downcasted to uint64 as uint64 has 18,446,744,073,709,551,616 places
        // as each round is 152 x 5 = 760, each day has around 113 rounds which is 41245 in a year
        // it results 4.4724801e+14 years to run this game
        return uint64(block.number / uint256(ROUND_LENGTH));
    }

    /**
     * @notice Return the price downscaled
     */
    function currentPrice() public view returns (uint32) {
        // We downcasted to uint32 and bitshift it by 2^10
        return uint32((currentPriceUpScaled) >> 10);
    }

    /**
     * @notice Return the price downscaled
     */
    function minimumPrice() public view returns (uint32) {
        // We downcasted to uint32 and bitshift it by 2^10
        return uint32((minimumPriceUpscaled) >> 10);
    }
}
