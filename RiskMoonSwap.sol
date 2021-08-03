pragma solidity ^0.8.4;
// SPDX-License-Identifier: UNLICENSED

// RISKMOON Token Swap

import "./Context.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";


contract RiskMoonSwap is Context, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    IERC20 public oToken;
    IERC20 public nToken;
    bool public swapEnabled;
    address public treasury;
    uint256 public swapDeadline;
    uint256 public swapStart;
    uint256 public supplyDecreaseRatio = 1;
    uint256 public supplyIncreaseRatio = 1;
    
    uint256 public oSwapped = 0;
    uint256 public nDistributed = 0;
    
    uint8 private swapRatioBase;
    uint8 private swapRatioVariable;
    
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    event Swapped(address investor, uint256 amount, uint256 received);

    constructor(address _oToken, address _nToken, uint256 _swapStart, address _treasury) {

        oToken = IERC20(_oToken);
        nToken = IERC20(_nToken);
        treasury = _treasury;
        
        swapEnabled = true;
        
        swapStart = _swapStart;
        swapDeadline = swapStart + 21 days;
        
        swapRatioBase = 100;
        swapRatioVariable = 16;
		
		supplyDecreaseRatio = 10000000;
    }
    
    function setSwapRatioBase(uint8 _value) external onlyOwner() {
        swapRatioBase = _value;
    }
    
    function setSwapRatioVariable(uint8 _value) external onlyOwner() {
        swapRatioVariable = _value;
    }
    
    function setSwapStart(uint256 timestamp) external onlyOwner() {
        swapStart = timestamp;
    }
    function setSwapDeadline(uint256 timestamp) external onlyOwner() {
        swapDeadline = timestamp;
    }

    function setNewToken(address _newToken) external onlyOwner {
        nToken = IERC20(_newToken);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
    
    function setSupplyDecreaseRatio(uint256 ratio) external onlyOwner {
        supplyDecreaseRatio = ratio;
    }
    
    function setSupplyIncreaseRatio(uint256 ratio) external onlyOwner {
        supplyIncreaseRatio = ratio;
    }

    modifier noContract() {
        require(
            Address.isContract(_msgSender()) == false,
            "Contracts are not allowed to interact with this contract"
        );
        _;
    }

    modifier canSwap() {
        require(block.timestamp >= swapStart, "Swap hasn't started yet");
        require(block.timestamp <= swapDeadline, "Swap has ended");
        require(swapEnabled == true, "Swap has been disabled");
        _;
    }

    function setSwapEnabled(bool _enabled) public onlyOwner {
        swapEnabled = _enabled;
    }
    
    function burnRemainingUnclaimedTokens() external onlyOwner {
        require(
            isDeadlineReached() == true,
            "Deadline to swap tokens has not been reached"
        );
        nToken.safeTransfer(
            burnAddress,
            nToken.balanceOf(address(this))
        );
    }

    function isDeadlineReached() public view returns (bool) {
        return block.timestamp > swapDeadline;
    }
    
    function getNewTokenBalance() public view returns (uint256) {
        return nToken.balanceOf(address(this));
    }
    
    function getOriginalTokenBalance() public view returns (uint256) {
        return oToken.balanceOf(address(this));
    }
    
    function getSwapRatio() public view returns (uint256) {
        uint256 swapRatio = 0;
        if(block.timestamp >= swapStart && block.timestamp <= swapDeadline) {
            uint256 totalTimeDiff = swapDeadline - swapStart;
            uint256 timeDiff = swapDeadline - block.timestamp;
            swapRatio = swapRatioBase + timeDiff.mul(swapRatioVariable).div(totalTimeDiff);
        }
        return swapRatio;
    }

    function performSwap() external noContract nonReentrant canSwap {
        uint256 amount = oToken.balanceOf(_msgSender());
        require(amount > 0, "You do not have original tokens to swap");
        uint256 swapRatio = getSwapRatio();
        uint256 swapAmount = amount.mul(swapRatio).div(100).mul(supplyIncreaseRatio).div(supplyDecreaseRatio);
        require(swapAmount > 0, "swapAmount is 0");
        require(nToken.balanceOf(address(this)) >= swapAmount, "Not enough of new token in contract");
        oToken.safeTransferFrom(_msgSender(), address(treasury), amount);
        nToken.safeTransfer(_msgSender(), swapAmount);
        oSwapped += amount;
        nDistributed += swapAmount;
        emit Swapped(_msgSender(), amount, swapAmount);
    }

    receive() external payable {
        revert();
    }

    // Function to allow owner to salvage BEP20 tokens sent to this contract (by mistake)
    function transferAnyBEP20Tokens(address _tokenAddr, uint _amount) public onlyOwner {
        IERC20 token = IERC20(_tokenAddr);
        require(treasury != address(0), "Treasury address must be set");
        token.safeTransfer(treasury, _amount);
    }
}
