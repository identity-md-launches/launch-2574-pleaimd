// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PleaIMD} from "../src/PleaIMD.sol";

/// @dev Local deployment fixture only; this is not a production launch factory or pool.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (PleaIMD) {
        return new PleaIMD{salt: salt}();
    }

    function distribute(PleaIMD token, address distributor, address pool, address remainder) external {
        uint256 supply = token.totalSupply();
        require(token.transfer(distributor, supply / 10));
        require(token.transfer(pool, supply * 8 / 10));
        require(token.transfer(remainder, supply / 10));
    }
}

contract PleaIMDLaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    function test_create2MintsOnlyToFactoryThenDistributionAndTransfersAreExact() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        address distributor = makeAddr("distributor fixture");
        address pool = makeAddr("pool balance fixture");
        address remainder = makeAddr("remainder fixture");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");
        PleaIMD token = factory.deploy(keccak256("local deployment"));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);

        factory.distribute(token, distributor, pool, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(token.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, SUPPLY / 10));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), SUPPLY / 10);

        // Exercises the token's pool-facing transfers; no pricing or AMM is simulated.
        vm.prank(pool);
        assertTrue(token.transfer(trader, 50 ether));
        assertEq(token.balanceOf(trader), 50 ether);
        vm.prank(trader);
        assertTrue(token.transfer(pool, 50 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeFitsEip170AndContainsNoReachableForbiddenOpcodes() public {
        PleaIMD token = new PleaIMD();
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);

        // Ignore PUSH data and unreachable compiler metadata, matching the supplied floor check.
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode == 0x5b) reachable = true;
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            if (reachable) {
                assertTrue(opcode != 0xf4, "DELEGATECALL");
                assertTrue(opcode != 0xf2, "CALLCODE");
                assertTrue(opcode != 0xff, "SELFDESTRUCT");
            }
            if (
                opcode == 0x00 || opcode == 0x56 || opcode == 0xf3 || opcode == 0xfd || opcode == 0xfe || opcode == 0xff
            ) {
                reachable = false;
            }
        }
    }
}
