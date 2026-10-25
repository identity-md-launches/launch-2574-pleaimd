// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaIMD} from "../src/PleaIMD.sol";

/// @dev All token movements stay within the actor set. An independent model tracks balances
/// and allowances, including self-transfers, approvals, revocations, and infinite allowances.
/// Rejected calls leave the model unchanged, so both invariants also check failure atomicity.
contract PleaIMDHandler is Test {
    PleaIMD public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(PleaIMD token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 ether;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function approveInfinite(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, type(uint256).max));
        expectedAllowance[owner][spender] = type(uint256).max;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, approved < balance ? approved : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function rejectTransferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        token.transfer(to, amount);
    }

    function rejectTransferToZero(uint256 fromSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    function rejectApprovalToZero(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
    }

    function rejectTransferFromOverAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 approved,
        uint256 excess
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approved = bound(approved, 0, type(uint256).max - 1);
        uint256 amount = bound(excess, approved + 1, type(uint256).max);
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        token.transferFrom(owner, to, amount);
    }

    function rejectTransferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        token.transferFrom(owner, to, amount);
    }

    function rejectTransferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(owner, address(0), amount);
    }

    /// @dev Exercise a nonzero full-balance transfer even if most actors are empty. Neither leg
    /// may tax, freeze, or mint, and the round trip must restore the state after any prior history.
    function fullBalanceRoundTrip(uint256 fromSeed) external {
        uint256 index = fromSeed % actors.length;
        while (expectedBalance[actors[index]] == 0) {
            index = (index + 1) % actors.length;
        }
        address from = actors[index];
        address to = actors[(index + 1) % actors.length];
        uint256 amount = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), toBefore + amount);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), amount);
        assertEq(token.balanceOf(to), toBefore);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PleaIMDInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    PleaIMD internal token;
    PleaIMDHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new PleaIMD();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        token.transfer(actors[0], SUPPLY);
        handler = new PleaIMDHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = PleaIMDHandler.transfer.selector;
        selectors[1] = PleaIMDHandler.approve.selector;
        selectors[2] = PleaIMDHandler.approveInfinite.selector;
        selectors[3] = PleaIMDHandler.revoke.selector;
        selectors[4] = PleaIMDHandler.transferFrom.selector;
        selectors[5] = PleaIMDHandler.rejectTransferOverBalance.selector;
        selectors[6] = PleaIMDHandler.rejectTransferToZero.selector;
        selectors[7] = PleaIMDHandler.rejectApprovalToZero.selector;
        selectors[8] = PleaIMDHandler.rejectTransferFromOverAllowance.selector;
        selectors[9] = PleaIMDHandler.rejectTransferFromOverBalance.selector;
        selectors[10] = PleaIMDHandler.rejectTransferFromToZero.selector;
        selectors[11] = PleaIMDHandler.fullBalanceRoundTrip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_fixedSupplyAndExactBalances() public view {
        uint256 balances;
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]));
            balances += token.balanceOf(actors[i]);
        }
        assertEq(balances, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchIndependentModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    function invariant_metadataIsStable() public view {
        assertEq(token.name(), "PleaIMD");
        assertEq(token.symbol(), "PLEA");
        assertEq(token.decimals(), 18);
    }
}
