// SPDX-License-Identifier: AGPL V3.0

pragma solidity >=0.6.0 <0.8.0;

pragma experimental ABIEncoderV2;

import "@ozUpgradesV3/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@ozUpgradesV3/contracts/token/ERC20/SafeERC20Upgradeable.sol";
import "@ozUpgradesV3/contracts/utils/AddressUpgradeable.sol";
import "@ozUpgradesV3/contracts/math/SafeMathUpgradeable.sol";
import "@ozUpgradesV3/contracts/access/OwnableUpgradeable.sol";
import "@ozUpgradesV3/contracts/utils/ReentrancyGuardUpgradeable.sol";

import "../../../interfaces/yearnV2/IVaultV2.sol";
import "../../../interfaces/yearnV1/IVaultSavings.sol";

import "@ozUpgradesV3/contracts/utils/PausableUpgradeable.sol";

contract VaultSavingsV2 is IVaultSavings, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    uint256 constant MAX_UINT256 = uint256(-1);

    using SafeERC20Upgradeable  for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    struct VaultInfo {
        bool isActive;
        uint256 blockNumber;
    }

    address[] internal registeredVaults;
    mapping(address => VaultInfo) vaults;

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    
    // deposit, withdraw
    /// if_succeeds {:msg "wrong length of vaults"} _vaults.length > 0;
    /// if_succeeds {:msg "wrong length of amounts"} _vaults.length == _amounts.length;
    /// if_succeeds {:msg "paused"} paused() == false;
    function deposit(address[] calldata _vaults, uint256[] calldata _amounts) external override nonReentrant whenNotPaused {
        require(_vaults.length == _amounts.length, "Size of arrays does not match");
        
        for (uint256 i=0; i < _vaults.length; i++) {
            _deposit(_vaults[i], _amounts[i]);
        }
    }

    /// if_succeeds {:msg "paused"} paused() == false;
    function deposit(address _vault, uint256 _amount) external override nonReentrant whenNotPaused returns(uint256 lpAmount)  {
        lpAmount = _deposit(_vault, _amount);
    }


    /// if_succeeds {:msg "wrong vault"} address(_vault) != address(0) && isVaultRegistered(_vault) && isVaultActive(_vault);
    /// if_succeeds {:msg "wrong amount"} _amount > 0;
    /// if_succeeds {:msg "paused"} paused() == false;
    /// if_succeeds {:msg "wrong balance at this contract"} old(IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(address(this))) == IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(address(this));
    /// if_succeeds {:msg "wrong balance at vault"} old(IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(address(_vault))) + _amount == IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(address(_vault));
    /// if_succeeds {:msg "wrong balance at msg.sender"} old(IERC20Upgradeable(_vault).balanceOf(msg.sender)) < IERC20Upgradeable(_vault).balanceOf(msg.sender);
    function _deposit(address _vault, uint256 _amount) internal returns(uint256 lpAmount) {
        require(_amount > 0, "Depositing zero amount");
        //check vault
        require(isVaultRegistered(_vault), "Vault is not Registered");
        require(isVaultActive(_vault),"Vault is not Active");
        require(!IVaultV2(_vault).emergencyShutdown(), "Vault is emergency shutdown");
        address baseToken = IVaultV2(_vault).token();
     
        //transfer token if it is allowed to contract
        IERC20Upgradeable(baseToken).safeTransferFrom(msg.sender, address(this), _amount);

        //set allowence to vault
        IERC20Upgradeable(baseToken).safeIncreaseAllowance(_vault, _amount);

        //deposit token to vault
        IVaultV2(_vault).deposit(_amount, address(this));

        lpAmount = IERC20Upgradeable(_vault).balanceOf(address(this));
        //send new tokens to user
        IERC20Upgradeable(_vault).safeTransfer(msg.sender, lpAmount);

        emit  Deposit(_vault, msg.sender, _amount, lpAmount);
    }


    /// if_succeeds {:msg "wrong length of vaults"} _vaults.length > 0;
    /// if_succeeds {:msg "wrong length of amounts"} _vaults.length == _amounts.length;
    /// if_succeeds {:msg "paused"} paused() == false;
    function withdraw(address[] calldata _vaults, uint256[] calldata _amounts) external override nonReentrant whenNotPaused {
        require(_vaults.length == _amounts.length, "Size of arrays does not match");

        for (uint256 i=0; i < _vaults.length; i++) {
            _withdraw(_vaults[i], _amounts[i]);
        }

    }

    /// if_succeeds {:msg "paused"} paused() == false;
    function withdraw(address _vault, uint256 _amount) external override nonReentrant whenNotPaused returns(uint256 baseAmount) {
        baseAmount = _withdraw(_vault, _amount);
    }

    /// if_succeeds {:msg "wrong vault"} address(_vault) != address(0) && isVaultRegistered(_vault) && isVaultActive(_vault);
    /// if_succeeds {:msg "wrong amount"} _amount > 0;
    /// if_succeeds {:msg "wrong balance at this contract"} old(IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(address(this))) == IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(address(this));
    /// if_succeeds {:msg "wrong balance at vault"} old(IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(_vault)) > IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(_vault);
    /// if_succeeds {:msg "wrong balance at msg.sender"} old(IERC20Upgradeable(_vault).balanceOf(msg.sender)) - _amount == IERC20Upgradeable(_vault).balanceOf(msg.sender);
    /// if_succeeds {:msg "wrong balance at msg.sender"} old(IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(msg.sender)) < IERC20Upgradeable(IVaultV2(_vault).token()).balanceOf(msg.sender);
    function _withdraw(address _vault, uint256 _amount) internal returns(uint256 baseAmount) {
        require(_amount > 0, "Withdrawing zero amount");
        require(isVaultRegistered(_vault), "Vault is not Registered");
        require(isVaultActive(_vault),"Vault is not Active");
        require(!IVaultV2(_vault).emergencyShutdown(), "Vault is emergency shutdown");
        //transfer LP Token if it is allowed to contract
        IERC20Upgradeable(_vault).safeTransferFrom(msg.sender, address(this), _amount);

        //burn tokens from vault
        IVaultV2(_vault).withdraw(_amount, address(this), 1); // maxLoss - default from VaultV2

        address baseToken = IVaultV2(_vault).token();

        baseAmount = IERC20Upgradeable(baseToken).balanceOf(address(this));

        //Transfer token to user
        IERC20Upgradeable(baseToken).safeTransfer(msg.sender, baseAmount);

        emit Withdraw(_vault, msg.sender, baseAmount, _amount);
    }

    /// if_succeeds {:msg "wrong vault"} _vault != address(0);
    /// if_succeeds {:msg "not registered"} vaults[_vault].isActive && vaults[_vault].blockNumber == block.number;
    /// if_succeeds {:msg "onlyOwner"} old(msg.sender == owner());
    function registerVault(address _vault) external override onlyOwner {
        require(!isVaultRegistered(_vault), "Vault is already registered");

        registeredVaults.push(_vault);

        vaults[_vault] = VaultInfo({
            isActive: true,
            blockNumber: block.number
        });

        address baseToken = IVaultV2(_vault).token();

        emit VaultRegistered(_vault, baseToken);
    }

    /// if_succeeds {:msg "wrong vault"} _vault != address(0);
    /// if_succeeds {:msg "not activated"} vaults[_vault].isActive && vaults[_vault].blockNumber == block.number;
    /// if_succeeds {:msg "onlyOwner"} old(msg.sender == owner());
    function activateVault(address _vault) external override onlyOwner {
        require(isVaultRegistered(_vault), "Vault is not registered");
    
        vaults[_vault] = VaultInfo({
            isActive: true,
            blockNumber: block.number
        });

       emit VaultActivated(_vault);

    }

    /// if_succeeds {:msg "wrong vault"} _vault != address(0);
    /// if_succeeds {:msg "not deactivated"} vaults[_vault].isActive == false && vaults[_vault].blockNumber == block.number;
    /// if_succeeds {:msg "onlyOwner"} old(msg.sender == owner());
    function deactivateVault(address _vault) external override onlyOwner {
        require(isVaultRegistered(_vault), "Vault is not registered");
    
        vaults[_vault] = VaultInfo({
            isActive: false,
            blockNumber: block.number
        });

       emit VaultDisabled(_vault);
    }

    /// if_succeeds {:msg "not paused"} paused() == true;
    /// if_succeeds {:msg "onlyOwner"} old(msg.sender == owner());
    function pause() external onlyOwner {
        _pause();
    }

    /// if_succeeds {:msg "paused"} paused() == false;
    /// if_succeeds {:msg "onlyOwner"} old(msg.sender == owner());
    function unpause() external onlyOwner {
        _unpause();
    }
    

    //view functions
    function isVaultRegistered(address _vault) public override view returns(bool) {
        for (uint256 i = 0; i < registeredVaults.length; i++){
            if (registeredVaults[i] == _vault) return true;
        }
        return false;
    }

    function isVaultActive(address _vault) public override view returns(bool) {

        return vaults[_vault].isActive;
    }

    function isBaseTokenForVault(address _vault, address _token) public override view returns(bool) {
        address baseToken = IVaultV2(_vault).token();
        if (baseToken == _token) return true;
        return false;
    }

    function supportedVaults() external override view returns(address[] memory) {
        return registeredVaults;
    }

    function activeVaults()  external override view returns(address[] memory _vaults) {  
        uint256 j = 0;
        for (uint256 i = 0; i < registeredVaults.length; i++) {
            if (vaults[registeredVaults[i]].isActive) {
                j = j.add(1);
            }
        }
        if (j > 0) {
            _vaults = new address[](j);
            j = 0;
            for (uint256 i = 0; i < registeredVaults.length; i++) {
                if (vaults[registeredVaults[i]].isActive) {
                    _vaults[j] = registeredVaults[i]; 
                    j = j.add(1);
                }
            }
        }
    }   
}