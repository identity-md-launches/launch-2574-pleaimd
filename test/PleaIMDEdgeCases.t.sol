// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaIMD} from "src/PleaIMD.sol";

/// @dev Complements the original deployment and ERC-20 suite with allowance boundaries,
/// authorization isolation, failure recovery, and algebraic properties of transfers.
/// forge-config: default.fuzz.runs = 1024
contract PleaIMDEdgeCasesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    PleaIMD internal token;
    address internal alice = makeAddr("edge alice");
    address internal bob = makeAddr("edge bob");
    address internal spender = makeAddr("edge spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new PleaIMD();
    }

    function test_oneBaseUnitCanMoveAndReturnWithoutRounding() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fundedSelfTransferStillRejectsOneOverBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferCannotWrapBalancesEvenWithInfiniteApproval() public {
        bytes memory error = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(error);
        token.transfer(alice, type(uint256).max);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        vm.expectRevert(error);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_exhaustedAllowanceCannotBeSpentTwice() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_delegatedSelfTransferConsumesApprovalWithoutChangingBalance() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalInOppositeDirectionGrantsNoAuthority() public {
        assertTrue(token.transfer(alice, 10));
        vm.prank(spender);
        assertTrue(token.approve(alice, type(uint256).max));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(spender, alice), type(uint256).max);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_approvalForOneOwnerCannotSpendAnotherOwnersTokens() public {
        assertTrue(token.transfer(alice, 20));
        assertTrue(token.transfer(bob, 30));
        vm.prank(alice);
        assertTrue(token.approve(spender, 20));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(bob, alice, 1);
        assertEq(token.allowance(alice, spender), 20);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), 20);
        assertEq(token.balanceOf(bob), 30);

        vm.prank(bob);
        assertTrue(token.approve(spender, 7));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 5));
        assertEq(token.allowance(alice, spender), 15);
        assertEq(token.allowance(bob, spender), 7);
        vm.prank(spender);
        assertTrue(token.transferFrom(bob, alice, 7));
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.allowance(alice, spender), 15);
        assertEq(token.balanceOf(alice), 22);
        assertEq(token.balanceOf(bob), 28);
    }

    function test_infiniteApprovalCanBeReplacedAfterSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_zeroAddressIsInvalidEvenForZeroApprovalOrDelegatedTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementIsIdempotentAndIndependentOfBalance(uint256 first, uint256 replacement)
        public
    {
        vm.startPrank(alice);
        assertTrue(token.approve(spender, first));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(alice, spender), replacement);
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        assertEq(token.allowance(alice, spender), replacement);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_largeFiniteAllowanceIsDecremented(uint256 approved, uint256 amount) public {
        approved = bound(approved, SUPPLY + 1, type(uint256).max - 1);
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedSpendPreservesApprovalForRetryAfterFunding(uint256 balance, uint256 shortfall) public {
        balance = bound(balance, 0, SUPPLY - 1);
        shortfall = bound(shortfall, 1, SUPPLY - balance);
        uint256 amount = balance + shortfall;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);

        assertTrue(token.transfer(alice, shortfall));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_rejectedRecipientPreservesApprovalForValidRetry(uint256 amount, bool infinite) public {
        amount = bound(amount, 1, SUPPLY);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), infinite ? approved : 0);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splittingTransfersHasSameResultAsSingleTransfer(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        PleaIMD singleTransferToken = new PleaIMD();
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, second));
        assertTrue(singleTransferToken.transfer(alice, first + second));
        assertEq(token.balanceOf(alice), singleTransferToken.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), singleTransferToken.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleTransferToken.totalSupply(), SUPPLY);
    }
}
