// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";

/// @title EIP712Helper
/// @notice Helper contract for EIP-712 signature generation in tests
/// @dev Uses Foundry's vm.eip712HashStruct cheatcode for canonical hashing
abstract contract EIP712Helper is Test {
    // Type definitions for EIP-712 structs
    string internal constant CHEQUE_TYPE = "Cheque(address chequebook,address beneficiary,uint256 cumulativePayout)";
    string internal constant CASHOUT_TYPE =
        "Cashout(address chequebook,address sender,uint256 requestPayout,address recipient,uint256 callerPayout)";
    string internal constant CUSTOMDECREASETIMEOUT_TYPE =
        "CustomDecreaseTimeout(address chequebook,address beneficiary,uint256 decreaseTimeout)";

    // Domain separator components
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId)");

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Chequebook"), keccak256("1.0"), block.chainid));
    }

    function signCheque(uint256 privateKey, address chequebook, address beneficiary, uint256 cumulativePayout)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = vm.eip712HashStruct(CHEQUE_TYPE, abi.encode(chequebook, beneficiary, cumulativePayout));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signCashout(
        uint256 privateKey,
        address chequebook,
        address sender,
        uint256 requestPayout,
        address recipient,
        uint256 callerPayout
    ) internal view returns (bytes memory) {
        bytes32 structHash = vm.eip712HashStruct(
            CASHOUT_TYPE, abi.encode(chequebook, sender, requestPayout, recipient, callerPayout)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signCustomDecreaseTimeout(
        uint256 privateKey,
        address chequebook,
        address beneficiary,
        uint256 decreaseTimeout
    ) internal view returns (bytes memory) {
        bytes32 structHash = vm.eip712HashStruct(
            CUSTOMDECREASETIMEOUT_TYPE, abi.encode(chequebook, beneficiary, decreaseTimeout)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
