// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice This code creates a minimal account based on account abstraction
contract MinimalAccount is IAccount, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted when a function is called from an address that is not the entry point.
    error MinimalAccount__NotFromEntryPoint();

    /// @dev Emitted when a function is called from an address that is not the entry point or the owner.
    error MinimalAccount__NotFromEntryPointOrOwner();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IEntryPoint private immutable i_entryPoint;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert MinimalAccount__NotFromEntryPoint();
        }
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != address(i_entryPoint) && msg.sender != owner()) {
            revert MinimalAccount__NotFromEntryPointOrOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @param entryPoint The address of the entry point contract.
    constructor(address entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(entryPoint);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    /// @notice Execute a transaction (called directly from owner, or by entryPoint)
    /// @param dest Address of the contract to call.
    /// @param value value to pass in this call.
    /// @param functionData the calldata to pass in this call.
    function execute(address dest, uint256 value, bytes calldata functionData) external requireFromEntryPointOrOwner {
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// Validate the signature is valid for this message.
    /// @param userOp          - Validate the userOp.signature field.
    /// @param userOpHash      - Convenient field: the hash of the request, to check the signature against.
    ///                          (also hashes the entrypoint and chain id)
    /// @return validationData - Signature and time-range of this operation.
    ///                          <20-byte> aggregatorOrSigFail - 0 for valid signature, 1 to mark signature failure,
    ///                           otherwise, an address of an aggregator contract.
    ///                          <6-byte> validUntil - last timestamp this operation is valid. 0 for "indefinite"
    ///                          <6-byte> validAfter - first timestamp this operation is valid
    ///                          If the account doesn't use time-range, it is enough to return
    ///                          SIG_VALIDATION_FAILED value (1) for signature failure.
    ///                          Note that the validation code cannot use block.timestamp (or block.number) directly.
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /// @param missingAccountFunds - The minimum value this method should send the entrypoint.
    ///                              This value MAY be zero, in case there is enough deposit,
    ///                              or the userOp has a paymaster.
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            (success);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW AND PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @return The address of the entry point contract.
    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }

    /// @notice This method returns the next sequential nonce.
    /// @dev For a nonce of a specific key, use `entrypoint.getNonce(account, key)`
    /// @return Return the account nonce.
    function getNonce() public view virtual returns (uint256) {
        return i_entryPoint.getNonce(address(this), 0);
    }

    /// @notice Check current account deposit in the entryPoint
    function getDeposit() public view returns (uint256) {
        return i_entryPoint.balanceOf(address(this));
    }

    /// @notice Deposit funds to this account in the entrypoint.
    function addDeposit() public payable {
        i_entryPoint.depositTo{value: msg.value}(address(this));
    }
}
