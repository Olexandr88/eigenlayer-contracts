// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;


interface IStakeRootCompendium {

    function getOperatorSetRoot(address avs, uint32 operatorSetId, address[] operators, address[] strategies) external view returns (bytes32);

    function getStakeRoot(address[] calldata avss, bytes32[] calldata operatorSetRoots) external view returns (bytes32);

    function verifySnarkProof(
        bytes calldata _journal,
        bytes calldata _seal
    ) external;

    function setImageId(bytes32 _imageId) external;

    function setVerifier(address _verifier) external;
}