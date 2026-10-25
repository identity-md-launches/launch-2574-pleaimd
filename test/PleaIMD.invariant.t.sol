// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PleaIMD} from "../src/PleaIMD.sol";

/// @dev All token movements stay within the actor set. An independent model tracks balances
/// and allowances, including self-transfers, approvals, revocations, and infinite allowances.
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
}

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
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PleaIMDHandler.transfer.selector;
        selectors[1] = PleaIMDHandler.approve.selector;
        selectors[2] = PleaIMDHandler.approveInfinite.selector;
        selectors[3] = PleaIMDHandler.revoke.selector;
        selectors[4] = PleaIMDHandler.transferFrom.selector;
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
    }

    function invariant_allowancesMatchIndependentModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
