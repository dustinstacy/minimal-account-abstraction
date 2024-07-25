//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {SendPackedUserOp, PackedUserOperation, IEntryPoint} from "script/SendPackedUserOp.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DeployMinimalAccount} from "script/DeployMinimalAccount.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    SendPackedUserOp sendPackedUserOp;
    ERC20Mock usdc;
    IEntryPoint entryPoint;

    address user = makeAddr("user");

    uint256 constant AMOUNT = 1e18;
    address dest;
    uint256 value;
    bytes functionData;
    bytes executeCallData;
    PackedUserOperation packedUserOp;
    bytes32 userOpHash;
    uint256 missingAccountFunds = 1e18;

    function setUp() public {
        DeployMinimalAccount deployMinimalAccount = new DeployMinimalAccount();
        (helperConfig, minimalAccount) = deployMinimalAccount.deployMinimalAccount();
        sendPackedUserOp = new SendPackedUserOp();
        usdc = new ERC20Mock();
        entryPoint = IEntryPoint(helperConfig.getConfig().entryPoint);
    }

    modifier createFunctionCallData() {
        dest = address(usdc);
        value = 0;
        functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        _;
    }

    modifier executeAndGenerateUserOp() {
        executeCallData = abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            helperConfig.getConfig(), executeCallData, address(minimalAccount)
        );
        userOpHash = entryPoint.getUserOpHash(packedUserOp);
        _;
    }

    function testOwnerCanExecuteCommands() public createFunctionCallData {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function test_RevertsIf_NonOwnerAttemptsToExecuteCommands() public createFunctionCallData {
        vm.prank(user);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    function test_RecoverSignedOp() public createFunctionCallData executeAndGenerateUserOp {
        address actualSigner = ECDSA.recover(userOpHash.toEthSignedMessageHash(), packedUserOp.signature);
        assertEq(actualSigner, minimalAccount.owner());
    }

    function test_ValidateUserOp() public createFunctionCallData executeAndGenerateUserOp {
        vm.prank(address(entryPoint));
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOpHash, missingAccountFunds);
        assertEq(validationData, 0);
    }

    function test_EntryPointCanExecuteCommands() public createFunctionCallData executeAndGenerateUserOp {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        vm.deal(address(minimalAccount), missingAccountFunds);
        vm.prank(user);
        entryPoint.handleOps(ops, payable(user));

        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }
}
