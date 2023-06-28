// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;


import "../interfaces/IIndexRegistry.sol";
import "../interfaces/IRegistryCoordinator.sol";
import "../libraries/BN254.sol";

contract IndexRegistry is IIndexRegistry {

    IRegistryCoordinator public immutable registryCoordinator;

    // list of all unique registered operators
    bytes32[] public globalOperatorList;

    // mapping of operatorId => quorumNumber => index history of that operator
    mapping(bytes32 => mapping(uint8 => OperatorIndexUpdate[])) internal _operatorIdToIndexHistory;
    // mapping of quorumNumber => history of numbers of unique registered operators
    mapping(uint8 => OperatorIndexUpdate[]) internal _totalOperatorsHistory;

    modifier onlyRegistryCoordinator() {
        require(msg.sender == address(registryCoordinator), "IndexRegistry.onlyRegistryCoordinator: caller is not the registry coordinator");
        _;
    }

    constructor(
        IRegistryCoordinator _registryCoordinator
    ){
        registryCoordinator = _registryCoordinator;
    }

    /**
     * @notice Registers the operator with the specified `operatorId` for the quorums specified by `quorumNumbers`.
     * @param operatorId is the id of the operator that is being registered
     * @param quorumNumbers is the quorum numbers the operator is registered for
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already registered
     */
    function registerOperator(bytes32 operatorId, bytes calldata quorumNumbers) external onlyRegistryCoordinator {
        //add operator to operatorList
        globalOperatorList.push(operatorId);

        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            //this is the would-be index of the operator being registered, the total number of operators for that quorum (which is last index + 1)
            uint256 quorumHistoryLength = _totalOperatorsHistory[quorumNumber].length;
            uint32 numOperators = quorumHistoryLength > 0 ? _totalOperatorsHistory[quorumNumber][quorumHistoryLength - 1].index : 0;
            _updateOperatorIdToIndexHistory(operatorId, quorumNumber, numOperators);
            _updateTotalOperatorHistory(quorumNumber, numOperators + 1);
        }
    }

    /**
     * @notice Deregisters the operator with the specified `operatorId` for the quorums specified by `quorumNumbers`.
     * @param operatorId is the id of the operator that is being deregistered
     * @param completeDeregistration Whether the operator is deregistering from all quorums or just some.
     * @param quorumNumbers is the quorum numbers the operator is deregistered for
     * @param operatorIdsToSwap is the list of operatorIds that have the largest indexes in each of the `quorumNumbers`
     * they will be swapped with the operator's current index when the operator is removed from the list
     * @param globalOperatorListIndex is the index of the operator that is to be removed from the list
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already deregistered
     *         5) `quorumNumbers` is a subset of the quorumNumbers that the operator is registered for
     */
    function deregisterOperator(bytes32 operatorId, bool completeDeregistration, bytes calldata quorumNumbers, bytes32[] memory operatorIdsToSwap, uint32 globalOperatorListIndex) external onlyRegistryCoordinator {
        require(quorumNumbers.length == operatorIdsToSwap.length, "IndexRegistry.deregisterOperator: quorumNumbers and operatorIdsToSwap must be the same length");

        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            uint32 indexOfOperatorToRemove = _operatorIdToIndexHistory[operatorId][quorumNumber][_operatorIdToIndexHistory[operatorId][quorumNumber].length - 1].index;
            _processOperatorRemoval(operatorId, quorumNumber, indexOfOperatorToRemove, operatorIdsToSwap[i]);
            _updateTotalOperatorHistory(quorumNumber, _totalOperatorsHistory[quorumNumber][_totalOperatorsHistory[quorumNumber].length - 1].index - 1);
        }

        // remove operator from globalOperatorList if this is a complete deregistration
        if(completeDeregistration){
            _removeOperatorFromGlobalOperatorList(globalOperatorListIndex);  
        }
    }

    /// @notice Returns the _operatorIdToIndexHistory entry for the specified `operatorId` and `quorumNumber` at the specified `index`
    function getOperatorIndexUpdateOfOperatorIdForQuorumAtIndex(bytes32 operatorId, uint8 quorumNumber, uint32 index) external view returns (OperatorIndexUpdate memory){
        return _operatorIdToIndexHistory[operatorId][quorumNumber][index];
    }

    /// @notice Returns the _totalOperatorsHistory entry for the specified `quorumNumber` at the specified `index`
    function getTotalOperatorsUpdateForQuorumAtIndex(uint8 quorumNumber, uint32 index) external view returns (OperatorIndexUpdate memory){
        return _totalOperatorsHistory[quorumNumber][index];
    }

    /**
     * @notice Looks up the `operator`'s index in the set of operators for `quorumNumber` at the specified `blockNumber` using the `index`.
     * @param operatorId is the id of the operator for which the index is desired
     * @param quorumNumber is the quorum number for which the operator index is desired
     * @param blockNumber is the block number at which the index of the operator is desired
     * @param index Used to specify the entry within the dynamic array `_operatorIdToIndexHistory[operatorId]` to 
     * read data from
     * @dev Function will revert in the event that the specified `index` input does not identify the appropriate entry in the
     * array `_operatorIdToIndexHistory[operatorId][quorumNumber]` to pull the info from.
     */
    function getOperatorIndexForQuorumAtBlockNumberByIndex(bytes32 operatorId, uint8 quorumNumber, uint32 blockNumber, uint32 index) external view returns (uint32){
        OperatorIndexUpdate memory operatorIndexToCheck = _operatorIdToIndexHistory[operatorId][quorumNumber][index];

        // blocknumber must be before the "index'th" entry's toBlockNumber
        require(blockNumber <= operatorIndexToCheck.toBlockNumber, "IndexRegistry.getOperatorIndexForQuorumAtBlockNumberByIndex: provided index is too far in the future for provided block number");
       
        // if there is an index update before the "index'th" update, the blocknumber must be after the previous entry's toBlockNumber
        if(index != 0){
            OperatorIndexUpdate memory previousOperatorIndex = _operatorIdToIndexHistory[operatorId][quorumNumber][index - 1];
            require(blockNumber > previousOperatorIndex.toBlockNumber, "IndexRegistry.getOperatorIndexForQuorumAtBlockNumberByIndex: provided index is too far in the past for provided block number");
        }
        return operatorIndexToCheck.index;
    }

    /**
     * @notice Looks up the number of total operators for `quorumNumber` at the specified `blockNumber`.
     * @param quorumNumber is the quorum number for which the total number of operators is desired
     * @param blockNumber is the block number at which the total number of operators is desired
     * @param index is the index of the entry in the dynamic array `_totalOperatorsHistory[quorumNumber]` to read data from
     */
    function getTotalOperatorsForQuorumAtBlockNumberByIndex(uint8 quorumNumber, uint32 blockNumber, uint32 index) external view returns (uint32){
        OperatorIndexUpdate memory operatorIndexToCheck = _totalOperatorsHistory[quorumNumber][index];

        // blocknumber must be before the "index'th" entry's toBlockNumber
        require(blockNumber <= operatorIndexToCheck.toBlockNumber, "IndexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex: provided index is too far in the future for provided block number");
        
        // if there is an index update before the "index'th" update, the blocknumber must be after the previous entry's toBlockNumber
        if (index != 0){
            OperatorIndexUpdate memory previousOperatorIndex = _totalOperatorsHistory[quorumNumber][index - 1];
            require(blockNumber > previousOperatorIndex.toBlockNumber, "IndexRegistry.getTotalOperatorsForQuorumAtBlockNumberByIndex: provided index is too far in the past for provided block number");
        }
        return operatorIndexToCheck.index;
    }

    /// @notice Returns an ordered list of operators of the services for the given `quorumNumber`
    function getOperatorListForQuorum(uint8 quorumNumber) external view returns (bytes32[] memory){
        bytes32[] memory quorumOperatorList = new bytes32[](_totalOperatorsHistory[quorumNumber][_totalOperatorsHistory[quorumNumber].length - 1].index);
        for (uint i = 0; i < globalOperatorList.length; i++) {
            bytes32 operatorId = globalOperatorList[i];
            if(_operatorIdToIndexHistory[operatorId][quorumNumber].length > 0){
                uint32 index = _operatorIdToIndexHistory[operatorId][quorumNumber][_operatorIdToIndexHistory[operatorId][quorumNumber].length - 1].index;
                quorumOperatorList[index - 1] = operatorId;
            }
        }
        return quorumOperatorList;
    }

    /// @notice Returns an index of the given `operatorId` in the global operator list
    function getIndexOfOperatorIdInGlobalOperatorList(bytes32 operatorId) external view returns (uint32){
        for (uint i = 0; i < globalOperatorList.length; i++) {
            if(globalOperatorList[i] == operatorId){
                return uint32(i);
            }
        }
        revert("IndexRegistry.getIndexOfOperatorIdInGlobalOperatorList: operatorId not found in globalOperatorList");
    }

    function totalOperatorsForQuorum(uint8 quorumNumber) external view returns (uint32){
        return _totalOperatorsHistory[quorumNumber][_totalOperatorsHistory[quorumNumber].length - 1].index;
    }


    /// @notice Returns the current number of operators of this service.
    function totalOperators() external view returns (uint32){
        return uint32(globalOperatorList.length);
    }

    /**
     * @notice updates the total numbers of operator in `quorumNumber` to `numOperators`
     * @param quorumNumber is the number of the quorum to update
     * @param numOperators is the number of operators in the quorum
     */
    function _updateTotalOperatorHistory(uint8 quorumNumber, uint32 numOperators) internal {
        uint256 totalOperatorsHistoryLength = _totalOperatorsHistory[quorumNumber].length;

        //if there is a prior entry, update its "toBlockNumber"
        if (totalOperatorsHistoryLength > 0) {
            _totalOperatorsHistory[quorumNumber][totalOperatorsHistoryLength - 1].toBlockNumber = uint32(block.number);
        }

        OperatorIndexUpdate memory totalOperatorUpdate;
        // In the case of totalOperatorsHistory, the index parameter is the number of operators in the quorum
        totalOperatorUpdate.index = numOperators;
        _totalOperatorsHistory[quorumNumber].push(totalOperatorUpdate);
    }

    /**
     * @param operatorId operatorId of the operator to update
     * @param quorumNumber quorumNumber of the operator to update
     * @param index the latest index of that operator in the list of operators registered for this quorum
     */ 
    function _updateOperatorIdToIndexHistory(bytes32 operatorId, uint8 quorumNumber, uint32 index) internal {
        uint256 operatorIdToIndexHistoryLength = _operatorIdToIndexHistory[operatorId][quorumNumber].length;
        //if there is a prior entry for the operator, set the previous entry's toBlocknumber
        if (operatorIdToIndexHistoryLength > 0) {
            _operatorIdToIndexHistory[operatorId][quorumNumber][operatorIdToIndexHistoryLength - 1].toBlockNumber = uint32(block.number);
        }
        OperatorIndexUpdate memory latestOperatorIndex;
        latestOperatorIndex.index = index;
        _operatorIdToIndexHistory[operatorId][quorumNumber].push(latestOperatorIndex);

        emit QuorumIndexUpdate(operatorId, quorumNumber, index);
    }

    /**
     * @notice when we remove an operator from a quorum, we simply update the operator's index history
     * as well as any operatorIds we have to swap
     * @param quorumNumber quorum number of the operator to remove
     * @param indexOfOperatorToRemove index of the operator to remove
     */ 
    function _processOperatorRemoval(bytes32 operatorId, uint8 quorumNumber, uint32 indexOfOperatorToRemove, bytes32 operatorIdToSwap) internal {   
        uint32 operatorIdToSwapIndex = _operatorIdToIndexHistory[operatorIdToSwap][quorumNumber][_operatorIdToIndexHistory[operatorIdToSwap][quorumNumber].length - 1].index;
        require(_totalOperatorsHistory[quorumNumber][_totalOperatorsHistory[quorumNumber].length - 1].index - 1 == operatorIdToSwapIndex, "IndexRegistry._processOperatorRemoval: operatorIdToSwap is not the last operator in the quorum");

        // if the operator is not the last in the list, we must swap the last operator into their positon
        if(operatorId != operatorIdToSwap){
            //update the swapped operator's operatorIdToIndexHistory list with a new entry, as their index has now changed
            _updateOperatorIdToIndexHistory(operatorIdToSwap, quorumNumber, indexOfOperatorToRemove);
        } 
        // marking the final entry in the deregistering operator's operatorIdToIndexHistory entry with the deregistration block number
        _operatorIdToIndexHistory[operatorId][quorumNumber][_operatorIdToIndexHistory[operatorId][quorumNumber].length - 1].toBlockNumber = uint32(block.number);
    }

    /**
     * @notice remove an operator from the globalOperatorList  
     * @param indexOfOperatorToRemove index of the operator to remove
     */ 
    function _removeOperatorFromGlobalOperatorList(uint32 indexOfOperatorToRemove) internal {
        uint32 globalOperatorListLastIndex = uint32(globalOperatorList.length - 1);
        bytes32 operatorIdToSwap;
        if(indexOfOperatorToRemove != globalOperatorListLastIndex){
            operatorIdToSwap = globalOperatorList[globalOperatorListLastIndex];
            globalOperatorList[indexOfOperatorToRemove] = operatorIdToSwap;
            emit GlobalIndexUpdate(operatorIdToSwap, indexOfOperatorToRemove);
        }
        globalOperatorList.pop();
    }
}