// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeploySwap} from "../../script/DeploySwap.s.sol";
import {TestToken} from "../../src/common/TestToken.sol";
import {SimpleSwapFactory} from "../../src/swap/SimpleSwapFactory.sol";
import {ERC20SimpleSwap} from "../../src/swap/ERC20SimpleSwap.sol";

contract DeploySwapTest is Test {
    DeploySwap public deployer;
    TestToken public token;

    uint256 internal deployerPk = 0x1;
    address internal deployerAddr;

    function setUp() public {
        deployerAddr = vm.addr(deployerPk);

        // Deploy a test token first
        token = new TestToken();

        // Set environment variables
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPk));
        vm.setEnv("BZZ_TOKEN", vm.toString(address(token)));

        deployer = new DeploySwap();
    }

    function test_run_deploysFactory() public {
        // Just verify the script runs without reverting
        deployer.run();
    }
}

contract DeploySwapIntegrationTest is Test {
    TestToken public token;
    SimpleSwapFactory public factory;

    address internal deployer;
    address internal issuer;
    address internal beneficiary;

    uint256 internal issuerPk = 0x1;
    uint256 internal beneficiaryPk = 0x2;

    uint256 internal constant DEFAULT_TIMEOUT = 1 days;
    uint256 internal constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        deployer = makeAddr("deployer");
        issuer = vm.addr(issuerPk);
        beneficiary = vm.addr(beneficiaryPk);

        // Deploy token
        token = new TestToken();

        // Deploy factory (simulating DeploySwap)
        vm.prank(deployer);
        factory = new SimpleSwapFactory(address(token));
    }

    function test_fullIntegration_factoryDeploysSwap() public {
        vm.prank(issuer);
        address swapAddr = factory.deploySimpleSwap(issuer, DEFAULT_TIMEOUT, bytes32(0));

        assertTrue(swapAddr != address(0));
        assertTrue(factory.deployedContracts(swapAddr));
    }

    function test_fullIntegration_swapCanCashCheque() public {
        // Deploy swap
        vm.prank(issuer);
        address swapAddr = factory.deploySimpleSwap(issuer, DEFAULT_TIMEOUT, bytes32(0));
        ERC20SimpleSwap swap = ERC20SimpleSwap(swapAddr);

        // Fund swap
        token.mint(swapAddr, INITIAL_BALANCE);

        // Issue and cash a cheque
        uint256 amount = 100 ether;
        bytes memory sig = signCheque(issuerPk, swapAddr, beneficiary, amount);

        vm.prank(beneficiary);
        swap.cashChequeBeneficiary(beneficiary, amount, sig);

        assertEq(token.balanceOf(beneficiary), amount);
        assertEq(swap.paidOut(beneficiary), amount);
    }

    function test_fullIntegration_multipleSwapsWork() public {
        // Deploy multiple swaps
        vm.startPrank(issuer);
        address swap1 = factory.deploySimpleSwap(issuer, DEFAULT_TIMEOUT, bytes32(uint256(1)));
        address swap2 = factory.deploySimpleSwap(issuer, DEFAULT_TIMEOUT, bytes32(uint256(2)));
        vm.stopPrank();

        assertTrue(swap1 != swap2);
        assertTrue(factory.deployedContracts(swap1));
        assertTrue(factory.deployedContracts(swap2));

        // Fund both swaps
        token.mint(swap1, INITIAL_BALANCE);
        token.mint(swap2, INITIAL_BALANCE);

        // Cash cheques from both
        uint256 amount1 = 50 ether;
        uint256 amount2 = 75 ether;

        bytes memory sig1 = signCheque(issuerPk, swap1, beneficiary, amount1);
        bytes memory sig2 = signCheque(issuerPk, swap2, beneficiary, amount2);

        vm.startPrank(beneficiary);
        ERC20SimpleSwap(swap1).cashChequeBeneficiary(beneficiary, amount1, sig1);
        ERC20SimpleSwap(swap2).cashChequeBeneficiary(beneficiary, amount2, sig2);
        vm.stopPrank();

        assertEq(token.balanceOf(beneficiary), amount1 + amount2);
    }

    // Helper function to sign a cheque using EIP-712
    function signCheque(
        uint256 privateKey,
        address chequebook,
        address _beneficiary,
        uint256 cumulativePayout
    ) internal view returns (bytes memory) {
        bytes32 DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId)");
        bytes32 CHEQUE_TYPEHASH = keccak256("Cheque(address chequebook,address beneficiary,uint256 cumulativePayout)");

        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("Chequebook"), keccak256("1.0"), block.chainid)
        );

        bytes32 structHash = keccak256(abi.encode(CHEQUE_TYPEHASH, chequebook, _beneficiary, cumulativePayout));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
