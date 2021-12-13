// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./Address.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./TokenSupport.sol";
import "./MarketOrders.sol";
import "./ERC1155Holder.sol";

/**
 * @dev Required interface of an ERC1155 compliant contract.
 */
interface IERC1155 {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) external;
    function safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external;
}

/**
 * @dev FreeMarkt.
 */
contract FreeMarket1155 is ERC1155Holder, ReentrancyGuard, MarketOrders, TokenSupport {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    IERC1155 public PlatoNft1155;    // NFT token of Plato
    address payable public govAddress;
    uint256 public fee = 500;
    uint256 public feeML = 1000;
    uint256 public baseMax = 10000;
    uint256 public constant itemMax = 1000000000;    // for calculate the itemId

    address public ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;          // ETH/BNB/HT/OKT
    
    event Sell(address indexed sender, address indexed currencyAddress, uint256 time, uint256 orderId, uint256 tokenId, uint256 price, uint256 amount);
    event Buy(address indexed sender, uint256 time, uint256 orderId, uint256 tokenId, uint256 amount);
    event Revoke(address indexed sender, uint256 time, uint256 orderId, uint256 tokenId, uint256 amount);
    event ModifyPrice(address indexed sender, uint256 time, uint256 orderId, uint256 newPrice);

    constructor(address _platoNft, address payable _gov) {
        require(_platoNft != address(0), "Nft zero address");
        require(_gov != address(0), "Gov zero address");

        PlatoNft1155 = IERC1155(_platoNft);
        govAddress = _gov;
        // init order
        Order memory _initOrder = Order(
            0,
            address(0),
            address(0),
            0,
            block.timestamp,
            block.timestamp,
            0,
            0,
            0
        );
        // init The array of tokenId
        orderList.push(_initOrder);
    }

    /**
     * @dev Add a order to list.
     */
    function placeOrder(address _currencyAddress, uint256 tokenId, uint256 amount, uint256 price) nonReentrant public {
        require(price > 0, "placeOrder: NFT price is 0");
        require(amount > 0, "placeOrder: NFT amount at least 1");
        address caller = _msgSender();
        require(PlatoNft1155.balanceOf(caller, tokenId) >= amount, "placeOrder: Insufficient balance of tokenId");

        require(_currencyAddress == ETH || _currencyAddress.isContract(), "placeOrder: The currency address is incorrect");

        PlatoNft1155.safeTransferFrom(caller, address(this), tokenId, amount, "0x");

        uint256 orderId = _add(Order({
            id: 0,
            owner: caller,
            currencyAddress: _currencyAddress,
            price: price, 
            createTime: block.timestamp,
            updateTime: 0,
            tokenId: tokenId,
            amount: amount, 
            remain: amount
        }));

        emit Sell(caller, _currencyAddress, block.timestamp, orderId, tokenId, price, amount);
    }

    /**
     * @dev Buy a order to tranfer nft.
     */
    function proxyTransfer(uint256 amount, uint256 index, Order memory order) internal {
        address caller = _msgSender();
        PlatoNft1155.safeTransferFrom(address(this), caller, order.tokenId, amount, "0x");

        if (order.remain == amount) {
            _remove(order.id);
        } else {
            orderList[index].remain = orderList[index].remain - amount;
        }

        emit Buy(caller, block.timestamp, order.id, order.tokenId, amount);
    }

    function checkOrder(uint256 amount, uint256 orderId) internal view returns(uint256 index, Order memory order) {
        require(amount > 0, "checkOrder: NFT purchase amount at least 1");
        index = orderIndex[orderId];
        require(contains(index), "checkOrder: Order not exists");

        order = at(index);
        address caller = _msgSender();
        require(order.owner != caller, "checkOrder: Buyer is owner of order");
        require(order.remain >= amount, "checkOrder: Order's nft not enough");

        return (index, order);
    }

    /**
     * @dev Buy a order in token.
     */
    function buyOrderInToken(uint256 amount, uint256 orderId) nonReentrant public {

        (uint256 index, Order memory order) = checkOrder(amount, orderId);
        
        uint256 _tokenAmt = order.price.mul(amount);
        address caller = _msgSender();
        require(
            _tokenAmt <= IERC20(order.currencyAddress).balanceOf(caller),
            "buyOrderInToken: insufficient balance"
        );

        if (fee > 0) {
            uint256 fee_ = _tokenAmt.mul(fee).div(baseMax);
            IERC20(order.currencyAddress).safeTransferFrom(caller, govAddress, fee_);
            _tokenAmt = _tokenAmt.sub(fee_);

            if (_tokenAmt > 0) {
                IERC20(order.currencyAddress).safeTransferFrom(caller, order.owner, _tokenAmt);
            }
        }

        proxyTransfer(amount, index, order);
    }

    /**
     * @dev Buy a order in eth.
     */
    function buyOrderInETH(uint256 amount, uint256 orderId) nonReentrant public payable {

        (uint256 index, Order memory order) = checkOrder(amount, orderId);

        require(order.currencyAddress == ETH, "buyOrderInETH: Non-eth order");
        
        uint256 _ethAmt = order.price.mul(amount);

        require(_ethAmt == msg.value, "buyOrderInETH: insufficient balance");

        if (fee > 0) {
            uint256 fee_ = _ethAmt.mul(fee).div(baseMax);
            govAddress.transfer(fee_);
            _ethAmt = _ethAmt.sub(fee_);

            if (_ethAmt > 0) {
                payable(order.owner).transfer(_ethAmt);
            }
        }

        proxyTransfer(amount, index, order);
    }

    /**
     * @dev Revoke a order to list.
     */
    function revokeOrder(uint256 orderId) nonReentrant public {

        uint256 index = orderIndex[orderId];
        require(contains(index), "revokeOrder: Order not exists");

        Order memory order_ = at(index);

        address caller = _msgSender();
        require(order_.owner == caller, "revokeOrder: Caller is not the owner of order");

        PlatoNft1155.safeTransferFrom(address(this), caller, order_.tokenId, order_.remain, "0x");

        _remove(order_.id);
        
        emit Revoke(caller, block.timestamp, orderId, order_.tokenId, order_.remain);
    }

    /**
     * @dev Revoke a order to list.
     */
    function modifyPrice(uint256 orderId, uint256 _newPrice) nonReentrant public {

        require(_newPrice > 0, "modifyPrice: new price cannot be 0");

        uint256 index = orderIndex[orderId];
        require(contains(index), "modifyPrice: Order not exists");
        address caller = _msgSender();
        require(at(index).owner == caller, "modifyPrice: Permit not call unless owner of order");

        orderList[index].price = _newPrice;
        orderList[index].updateTime = block.timestamp;

        emit ModifyPrice(caller, block.timestamp, orderId, _newPrice);
    }

    function getOrderById(uint256 orderId) public view
        returns(
            uint256 id,
            address owner,
            address currencyAddress,
            uint256 price,
            uint256 createTime,
            uint256 updateTime,
            uint256 tokenId,
            uint256 amount,
            uint256 remain
        )
    {
        uint256 index = orderIndex[orderId];
        require(contains(index), "getOrderById: Order not exists");

        return (
            at(index).id,
            at(index).owner,
            at(index).currencyAddress,
            at(index).price,
            at(index).createTime,
            at(index).updateTime,
            at(index).tokenId,
            at(index).amount,
            at(index).remain
        );
    }

    function setFee(uint256 _fee) public onlyOwner {
        require(_fee <= feeML,"setFee: fee over limit");
        fee = _fee;
    }

    // Prevent accidentally transferring the other token to the contract
    function inCaseTokensGetStuck(address _token, uint256 _amount, address _to) public onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function takeOutEth() public onlyOwner {
        payable(_msgSender()).transfer(address(this).balance);
    }
}
