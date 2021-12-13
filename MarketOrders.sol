// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./EnumerableSet.sol";
/**
 * @dev MarketOrders.
 */
contract MarketOrders {

    using EnumerableSet for EnumerableSet.UintSet;
    mapping (address => EnumerableSet.UintSet) private _holderOrderIds;

    struct Order {
        uint256 id;                 // order id
        address owner;              // owner of place order
        address currencyAddress;    // currency address of place order
        uint256 price;              // currency amount (price of per nft)
        uint256 createTime;         // The time of create order
        uint256 updateTime;         // The time of modify order
        uint256 tokenId;            // The tokenId of modify order
        uint256 amount;             // The amount of tokenId
        uint256 remain;             // The remaining amount of tokenId
    }

    uint256 public orderNonce;
    Order[] public orderList;

    mapping (uint256 => uint256) public orderIndex;    // orderId => orderIndex

    /**
     * @dev Add a order to list.
     * Returns true or false
     */
    function _add(Order memory _order) internal returns (uint256) {
        orderNonce++;
        _order.id = orderNonce;
        orderIndex[_order.id] = length();
        orderList.push(_order);
        _holderOrderIds[_order.owner].addSet(_order.id);

        return _order.id;
    }

    /**
     * @dev Removes the order from order list.
     * Returns true if the order was removed from the list.
     */
    function _remove(uint256 _orderId) internal returns (bool) {

        require(_orderId >= 1, "_remove: no orderId in list");
        require(orderList.length >= 1, "_remove: no order in list");

        uint256 index = orderIndex[_orderId];
        uint256 lastIndex = orderList.length - 1;

        if (orderIndex[_orderId] != lastIndex) {
            orderList[index] = orderList[lastIndex];
            orderIndex[orderList[index].id] = index;
        }

        _holderOrderIds[orderList[index].owner].remove(_orderId);
        orderList.pop();
        delete orderIndex[_orderId];

        return true;
    }

    /**
     * @dev Returns true if the order is in the list.
     */
    function contains(uint256 index) public view returns (bool) {
        return orderList[index].owner != address(0);
    }

    /**
     * @dev Returns the number of order on the list.
     */
    function length() public view returns (uint256) {
        return orderList.length;
    }

    /**
     * @dev Returns the order stored at position `index` in the list.
     * Requirements: - `index` must be strictly less than {length}.
     */
    function at(uint256 index) public view returns (Order memory) {
        require(length() > index, "MarketOrders: index out of bounds");
        return orderList[index];
    }

    function orderIdOfOwnerByIndex(address owner, uint256 index) public view returns (uint256) {
        return _holderOrderIds[owner].at(index);
    }

    function holderOrderIds(address account) public view returns (uint256) {
        require(account != address(0), "MarketOrders: holder orderIds query for the zero address");
        return _holderOrderIds[account].length();
    }

}
