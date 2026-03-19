// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

import {AutomatedMarketBook} from "../src/AutomatedMarketBook.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TestAutomatedMarketBook is Test {
    MockERC20 token1;
    MockERC20 token2;

    AutomatedMarketBook automatedMarketBook;

    address contractOwner;
    address user1;
    address user2;

    function setUp() public {
        contractOwner = makeAddr("contractOwner");

        token1 = new MockERC20("token1", "TK1");
        token2 = new MockERC20("token2", "TK2");

        vm.prank(contractOwner);
        automatedMarketBook = new AutomatedMarketBook();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        token1.mint(user1, 100 ether);
        token2.mint(user2, 100 ether);
    }

    function test__createNewCommodity() public {
        assertEq(automatedMarketBook.getCommodityStatus(address(token1)), false);

        vm.startPrank(contractOwner);
        automatedMarketBook.createNewCommodity(address(token1));
        vm.stopPrank();

        assertEq(automatedMarketBook.getCommodityStatus(address(token1)), true);
    }

    function test__createBuyOrder() public {
        vm.prank(contractOwner);
        automatedMarketBook.createNewCommodity(address(token1));

        vm.startPrank(user1);
        vm.expectRevert(AutomatedMarketBook.AutomatedMarketBook__OwnerDoesNotHaveFunds.selector);
        automatedMarketBook.setupBuyOrder(address(token1), 1 ether, 1, address(token2));
        vm.stopPrank();

        vm.startPrank(user2);
        token2.approve(address(automatedMarketBook), 2 ether);
        automatedMarketBook.setupBuyOrder(address(token1), 1 ether, 2, address(token2));
        vm.stopPrank();

        console.log(token2.balanceOf(user2));
    }

    function test__createSellOrder() public {
        vm.prank(contractOwner);
        automatedMarketBook.createNewCommodity(address(token1));

        vm.startPrank(user2);
        vm.expectRevert(AutomatedMarketBook.AutomatedMarketBook__OwnerDoesNotHaveFunds.selector);
        automatedMarketBook.setupSellOrder(address(token1), 1 ether, 1, address(token2));
        vm.stopPrank();

        vm.startPrank(user1);
        token1.approve(address(automatedMarketBook), 1 ether);
        automatedMarketBook.setupSellOrder(address(token1), 1 ether, 1, address(token2));
        vm.stopPrank();

        console.log(token1.balanceOf(user1));
    }

    function test__OrderMatching() public {
        vm.prank(contractOwner);
        automatedMarketBook.createNewCommodity(address(token1));

        vm.startPrank(user2);
        token2.approve(address(automatedMarketBook), 2 ether);
        AutomatedMarketBook.Order memory order =
            automatedMarketBook.setupBuyOrder(address(token1), 1 ether, 2, address(token2));
        vm.stopPrank();

        vm.startPrank(user1);
        token1.approve(address(automatedMarketBook), 1 ether);
        automatedMarketBook.setupSellOrder(address(token1), 1 ether, 1, address(token2));
        vm.stopPrank();

        automatedMarketBook.matchOrder(order);

        console.log("User 1 Token 1 Balance: ", token1.balanceOf(user1));
        console.log("User 1 Token 2 Balance: ", token2.balanceOf(user1));

        console.log("User 2 Token 1 Balance: ", token1.balanceOf(user2));
        console.log("User 2 Token 2 Balance: ", token2.balanceOf(user2));

        console.log("Contract Token 1 Balance: ", token1.balanceOf(address(automatedMarketBook)));
        console.log("Contract Token 2 Balance: ", token2.balanceOf(address(automatedMarketBook)));
    }

    function test__AutomatedOrderMatching() public {
        vm.prank(contractOwner);
        automatedMarketBook.createNewCommodity(address(token1));

        vm.startPrank(user2);
        token2.approve(address(automatedMarketBook), 3 ether);
        automatedMarketBook.setupBuyOrder(address(token1), 1 ether, 3, address(token2));
        vm.stopPrank();

        vm.startPrank(user1);
        token1.approve(address(automatedMarketBook), 2 ether);
        automatedMarketBook.setupSellOrderAndMatch(address(token1), 2 ether, 1, address(token2));
        vm.stopPrank();

        vm.startPrank(user1);
        token1.approve(address(automatedMarketBook), 2 ether);
        automatedMarketBook.setupSellOrder(address(token1), 1 ether, 1, address(token2));
        vm.stopPrank();

        (,,bool success) = automatedMarketBook.getMinSellOrder(address(token1), address(token2));

        console.log("Min sell order success: ", success);

        vm.startPrank(user2);
        token2.approve(address(automatedMarketBook), 4 ether);
        automatedMarketBook.setupBuyOrderAndMatch(address(token1), 2 ether, 2, address(token2));
        vm.stopPrank();

        console.log("User 1 Token 1 Balance: ", token1.balanceOf(user1));
        console.log("User 1 Token 2 Balance: ", token2.balanceOf(user1));

        console.log("User 2 Token 1 Balance: ", token1.balanceOf(user2));
        console.log("User 2 Token 2 Balance: ", token2.balanceOf(user2));

        console.log("Contract Token 1 Balance: ", token1.balanceOf(address(automatedMarketBook)));
        console.log("Contract Token 2 Balance: ", token2.balanceOf(address(automatedMarketBook)));
    }
}
