// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract AutomatedMarketBook {
    error AutomatedMarketBook__SenderIsNotOwner();
    error AutomatedMarketBook__OwnerDoesNotHaveFunds();
    error AutomatedMarketBook__AmountMustBeGreaterThanZero();
    error AutomatedMarketBook__PriceMustBeGreaterThanZero();
    error AutomatedMarketBook__TransactionFailed();
    error AutomatedMarketBook__NoOrdersFromOtherParties();
    error AutomatedMarketBook__OrderNotInList();

    enum OrderType {
        BUY,
        SELL
    }

    struct Order {
        address commodity; // address(0) for base commodity
        address account;
        uint256 amount;
        uint256 price;
        address purchasingCommodity;
        bool fulfilled;
        OrderType orderType;
    }

    address private immutable I_OWNER;

    address[] private commodities;
    mapping(address => bool) private commoditiesAvailable;
    mapping(address => Order[]) private buyOrders;
    mapping(address => Order[]) private sellOrders;

    modifier onlyOwner() {
        _checkOwner(msg.sender);
        _;
    }

    function _checkOwner(address who) internal view {
        require(who == I_OWNER, AutomatedMarketBook__SenderIsNotOwner());
    }

    constructor() {
        I_OWNER = msg.sender;
    }

    function createNewCommodity(address _commodity) public onlyOwner {
        commoditiesAvailable[_commodity] = true;
        commodities.push(_commodity);
    }

    function setupBuyOrder(address _commodity, uint256 _amount, uint256 _price, address _purchasingCommodity)
        public
        payable
        returns (Order memory order)
    {
        require(_amount > 0, AutomatedMarketBook__AmountMustBeGreaterThanZero());
        require(_price > 0, AutomatedMarketBook__PriceMustBeGreaterThanZero());

        if (_purchasingCommodity == address(0)) {
            require(msg.value >= _amount * _price, AutomatedMarketBook__OwnerDoesNotHaveFunds());
        } else {
            uint256 allowance = IERC20(_purchasingCommodity).allowance(msg.sender, address(this));
            require(allowance >= _amount * _price, AutomatedMarketBook__OwnerDoesNotHaveFunds());

            bool txStatus = IERC20(_purchasingCommodity).transferFrom(msg.sender, address(this), _amount * _price);
            require(txStatus, AutomatedMarketBook__TransactionFailed());
        }

        order = Order({
            commodity: _commodity,
            account: msg.sender,
            amount: _amount,
            price: _price,
            purchasingCommodity: _purchasingCommodity,
            fulfilled: false,
            orderType: OrderType.BUY
        });

        buyOrders[_commodity].push(order);
    }

    function setupBuyOrderAndMatch(address _commodity, uint256 _amount, uint256 _price, address _purchasingCommodity)
        public
        payable
        returns (Order memory order)
    {
        order = setupBuyOrder(_commodity, _amount, _price, _purchasingCommodity);
        matchBuyOrder(order);
    }

    function setupSellOrder(address _commodity, uint256 _amount, uint256 _price, address _purchasingCommodity)
        public
        payable
        returns (Order memory order)
    {
        require(_amount > 0, AutomatedMarketBook__AmountMustBeGreaterThanZero());
        require(_price > 0, AutomatedMarketBook__PriceMustBeGreaterThanZero());

        if (_commodity == address(0)) {
            require(msg.value >= _amount, AutomatedMarketBook__OwnerDoesNotHaveFunds());
        } else {
            uint256 allowance = IERC20(_commodity).allowance(msg.sender, address(this));
            require(allowance >= _amount, AutomatedMarketBook__OwnerDoesNotHaveFunds());

            bool txStatus = IERC20(_commodity).transferFrom(msg.sender, address(this), _amount);
            require(txStatus, AutomatedMarketBook__TransactionFailed());
        }

        order = Order({
            commodity: _commodity,
            account: msg.sender,
            amount: _amount,
            price: _price,
            purchasingCommodity: _purchasingCommodity,
            fulfilled: false,
            orderType: OrderType.SELL
        });

        sellOrders[_commodity].push(order);
    }

    function setupSellOrderAndMatch(address _commodity, uint256 _amount, uint256 _price, address _purchasingCommodity)
        public
        payable
        returns (Order memory order)
    {
        order = setupSellOrder(_commodity, _amount, _price, _purchasingCommodity);
        matchSellOrder(order);
    }

    function setupSellOrderAtSpot(address _commodity, uint256 _amount, address _purchasingCommodity)
        public
        payable
        returns (Order memory order)
    {}

    function orderMatching(Order memory _order) internal {
        if (_order.orderType == OrderType.BUY) {
            matchBuyOrder(_order);
        } else {
            matchSellOrder(_order);
        }
    }

    function matchBuyOrder(Order memory _order) internal {
        require(sellOrders[_order.commodity].length > 0, AutomatedMarketBook__NoOrdersFromOtherParties());

        bool complete = false;

        bool buyOrderFound = false;
        uint256 buyOrderIndex = 0;

        for (uint256 i = 0; i < buyOrders[_order.commodity].length; i++) {
            Order memory currentBuyOrder = buyOrders[_order.commodity][i];

            if (
                currentBuyOrder.account == _order.account && currentBuyOrder.price == _order.price
                    && currentBuyOrder.purchasingCommodity == _order.purchasingCommodity
                    && currentBuyOrder.orderType == _order.orderType && currentBuyOrder.fulfilled == _order.fulfilled
            ) {
                buyOrderIndex = i;
                buyOrderFound = true;
            }
        }

        require(buyOrderFound, AutomatedMarketBook__OrderNotInList());

        if (_order.fulfilled) {
            complete = true;
        }

        while (_order.amount > 0 && !complete) {
            complete = true;
            uint256 currentMin = 0;
            uint256 minIndex = 0;

            for (uint256 i = 0; i < sellOrders[_order.commodity].length; i++) {
                if (!sellOrders[_order.commodity][i].fulfilled) {
                    if (currentMin > sellOrders[_order.commodity][i].price) {
                        currentMin = sellOrders[_order.commodity][i].price;
                        minIndex = i;
                    }
                }
            }

            Order memory sellOrder = sellOrders[_order.commodity][minIndex];

            if (currentMin <= _order.price) {
                complete = false;
                if (sellOrder.amount >= _order.amount) {
                    sellOrder.amount = sellOrder.amount - _order.amount;

                    if (_order.commodity == address(0)) {
                        (bool txStatus,) = (_order.account).call{value: _order.amount}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    } else {
                        bool txStatus = IERC20(_order.commodity).transfer(_order.account, _order.amount);
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    }

                    if (_order.purchasingCommodity == address(0)) {
                        (bool txStatus,) = (sellOrder.account).call{value: sellOrder.price * _order.amount}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());

                        (txStatus,) = (_order.account).call{value: (_order.price - sellOrder.price) * _order.amount}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    } else {
                        bool txStatus = IERC20(_order.purchasingCommodity)
                            .transfer(sellOrder.account, sellOrder.price * _order.amount);
                        require(txStatus, AutomatedMarketBook__TransactionFailed());

                        txStatus = IERC20(_order.purchasingCommodity)
                            .transfer(_order.account, (_order.price - sellOrder.price) * _order.amount);
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    }

                    _order.amount = 0;

                    if (sellOrder.amount == 0) {
                        sellOrder.fulfilled = true;
                    }

                    sellOrders[_order.commodity][minIndex] = sellOrder; // Update order globally at the end (CEI)
                } else {
                    _order.amount = _order.amount - sellOrder.amount;

                    sellOrder.amount = 0;

                    sellOrder.fulfilled = true;

                    if (_order.commodity == address(0)) {
                        (bool txStatus,) = (_order.account).call{value: sellOrder.amount}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    } else {
                        bool txStatus = IERC20(_order.commodity).transfer(_order.account, sellOrder.amount);
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    }

                    if (_order.purchasingCommodity == address(0)) {
                        (bool txStatus,) = (sellOrder.account).call{value: sellOrder.amount * sellOrder.price}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());

                        (txStatus,) =
                            (_order.account).call{value: (_order.price - sellOrder.price) * sellOrder.amount}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    } else {
                        bool txStatus = IERC20(_order.purchasingCommodity)
                            .transfer(sellOrder.account, sellOrder.amount * sellOrder.price);

                        require(txStatus, AutomatedMarketBook__TransactionFailed());

                        txStatus = IERC20(_order.purchasingCommodity)
                            .transfer(_order.account, (_order.price - sellOrder.price) * sellOrder.amount);
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    }

                    sellOrders[_order.commodity][minIndex] = sellOrder;
                }

                if (_order.amount >= 0) {
                    complete = false;
                }
            }
        }

        if (_order.amount == 0) {
            _order.fulfilled = true;
        }

        buyOrders[_order.commodity][buyOrderIndex] = _order;
    }

    function matchSellOrder(Order memory _order) internal {
        require(buyOrders[_order.commodity].length > 0, AutomatedMarketBook__NoOrdersFromOtherParties());

        bool complete = false;

        bool sellOrderFound = false;
        uint256 sellOrderIndex = 0;

        for (uint256 i = 0; i < sellOrders[_order.commodity].length; i++) {
            Order memory currentSellOrder = sellOrders[_order.commodity][i];

            if (
                currentSellOrder.account == _order.account && currentSellOrder.price == _order.price
                    && currentSellOrder.purchasingCommodity == _order.purchasingCommodity
                    && currentSellOrder.orderType == _order.orderType && currentSellOrder.fulfilled == _order.fulfilled
            ) {
                sellOrderIndex = i;
                sellOrderFound = true;
            }
        }

        require(sellOrderFound, AutomatedMarketBook__OrderNotInList());

        if (_order.fulfilled) {
            complete = true;
        }

        while (_order.amount > 0 && !complete) {
            complete = true;
            uint256 currentMax = 0;
            uint256 minIndex = 0;

            for (uint256 i = 0; i < buyOrders[_order.commodity].length; i++) {
                if (!buyOrders[_order.commodity][i].fulfilled) {
                    if (currentMax < buyOrders[_order.commodity][i].price) {
                        currentMax = buyOrders[_order.commodity][i].price;
                        minIndex = i;
                    }
                }
            }

            Order memory buyOrder = buyOrders[_order.commodity][minIndex];

            if (currentMax >= _order.price) {
                complete = false;
                if (buyOrder.amount >= _order.amount) {
                    buyOrder.amount = buyOrder.amount - _order.amount;

                    if (_order.commodity == address(0)) {
                        (bool txStatus,) = (buyOrder.account).call{value: _order.amount}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    } else {
                        bool txStatus = IERC20(_order.commodity).transfer(buyOrder.account, _order.amount);
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    }

                    if (_order.purchasingCommodity == address(0)) {
                        (bool txStatus,) = (_order.account).call{value: buyOrder.price * _order.amount}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    } else {
                        bool txStatus =
                            IERC20(_order.purchasingCommodity).transfer(_order.account, buyOrder.price * _order.amount);
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    }

                    _order.amount = 0;

                    if (buyOrder.amount == 0) {
                        buyOrder.fulfilled = true;
                    }

                    buyOrders[_order.commodity][minIndex] = buyOrder; // Update order globally at the end (CEI)
                } else {
                    _order.amount = _order.amount - buyOrder.amount;

                    buyOrder.amount = 0;

                    buyOrder.fulfilled = true;

                    if (_order.commodity == address(0)) {
                        (bool txStatus,) = (buyOrder.account).call{value: buyOrder.amount}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    } else {
                        bool txStatus = IERC20(_order.commodity).transfer(buyOrder.account, buyOrder.amount);
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    }

                    if (_order.purchasingCommodity == address(0)) {
                        (bool txStatus,) = (_order.account).call{value: buyOrder.amount * buyOrder.price}("");
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    } else {
                        bool txStatus = IERC20(_order.purchasingCommodity)
                            .transfer(_order.account, buyOrder.amount * buyOrder.price);
                        require(txStatus, AutomatedMarketBook__TransactionFailed());
                    }

                    buyOrders[_order.commodity][minIndex] = buyOrder;
                }

                if (_order.amount >= 0) {
                    complete = false;
                }
            }
        }

        if (_order.amount == 0) {
            _order.fulfilled = true;
        }

        sellOrders[_order.commodity][sellOrderIndex] = _order;
    }

    function matchOrder(Order memory _order) public {
        orderMatching(_order);
    }

    function resetOrders() public onlyOwner {
        for (uint256 i = 0; i < commodities.length; i++) {
            commoditiesAvailable[commodities[i]] = false;
            delete buyOrders[commodities[i]];
            delete sellOrders[commodities[i]];
        }

        delete commodities;
    }

    function getOwner() public view returns (address) {
        return I_OWNER;
    }

    function getCommodityStatus(address _commodity) public view returns (bool) {
        return commoditiesAvailable[_commodity];
    }
}
