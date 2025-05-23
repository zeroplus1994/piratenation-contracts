// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.26;

import {GAME_LOGIC_CONTRACT_ROLE, VRF_CONSUMER_ROLE, MANAGER_ROLE, VRF_SYSTEM_ROLE} from "../Constants.sol";
import {IVRFSystem, ID} from "./IVRFSystem.sol";
import {GameRegistryConsumerUpgradeable} from "../GameRegistryConsumerUpgradeable.sol";
import {IVRFSystemOracle} from "./IVRFSystemOracle.sol";
import {IVRFSystemCallback} from "./IVRFSystemCallback.sol";

/// @notice Emitted when a random number request is initiated
/// @param requestId The unique identifier for the random number request
/// @param callbackAddress The address the random number is requested to
/// @param traceId The trace ID used to track the request across transactions (0 if no trace ID)
event RandomNumberRequested(uint256 indexed requestId, address indexed callbackAddress, uint256 indexed traceId);

/// @notice Emitted when a random number is successfully delivered
/// @param requestId The unique identifier of the fulfilled request
/// @param callbackAddress the adddress was random number is requested to
/// @param traceId The trace ID associated with the request
/// @param roundNumber The round number that was used for the random number
/// @param randomNumber The random number that was generated
event RandomNumberDelivered(uint256 indexed requestId, address indexed callbackAddress, uint256 indexed traceId, uint256 roundNumber, uint256 randomNumber);

/// @notice Thrown when attempting to deliver a random number for a non-existent request
error InvalidRequestId();
error InvalidCaller();

/**
 * Random number generator based off of Proof of Play VRF
 */
contract VRFSystem is IVRFSystemOracle, GameRegistryConsumerUpgradeable
{
    // Keep Track of Callbacks
    mapping(uint256 => IVRFSystemCallback) internal callbacks;
    // Keep track of TraceIds
    mapping(uint256 => uint256) public requestIdToTraceId; // Systems can Query the VRF now to get a traceId

    // Keep track of the requestId incrementing
    uint256 public requestId;

    /** SETUP **/
    function initialize(address gameRegistryAddress) public initializer {
        requestId = 0;
        __GameRegistryConsumer_init(gameRegistryAddress, ID);
    }

    /**
     * Issues a request for random number
     *
     * @param traceId            TraceId to use for the request (keeps track of one request over many transactions) - Use 0 if no traceId
     */
     function requestRandomNumberWithTraceId(uint256 traceId) external returns (uint256) {
         if (!_gameRegistry.hasAccessRole(GAME_LOGIC_CONTRACT_ROLE, msg.sender) && (!_gameRegistry.hasAccessRole(VRF_CONSUMER_ROLE, msg.sender))) {
             revert InvalidCaller();
         }

         requestId++;
         requestIdToTraceId[requestId] = traceId;
         callbacks[requestId] = IVRFSystemCallback(msg.sender);

         emit RandomNumberRequested(requestId, msg.sender, traceId);

         return requestId;
     }

    /**
     * @param id Id of the request to check
     * @return Whether or not a request with the given requestId is pending
     */
    function isRequestPending(uint256 id) external view returns (bool) {
        return address(callbacks[id]) != address(0);
    }

    /**
     * Callback for when the randomness process has completed
     * Called by only VRFs that have the VRF_SYSTEM_ROLE
     *
     * @param id   Id of the randomness request
     * @param randomNumber  Number generated by VRF
     */
     function deliverRandomNumber(
         uint256 id,
         uint256 roundNumber,
         uint256 randomNumber
     ) external override onlyRole(VRF_SYSTEM_ROLE) {
         IVRFSystemCallback callbackAddress = callbacks[id];
         if (address(callbackAddress) == address(0)) {
             revert InvalidRequestId();
         }

         uint256 traceId = requestIdToTraceId[id];
         delete callbacks[id];

         // note: keccak requestId here to add entropy so every call is not the same.
         uint256 keccakRandomNumber = uint256(
             keccak256(abi.encode(randomNumber, requestId))
         );
         callbackAddress.randomNumberCallback(id, keccakRandomNumber);

         emit RandomNumberDelivered(id, address(callbackAddress), traceId, roundNumber, randomNumber);
     }
}
