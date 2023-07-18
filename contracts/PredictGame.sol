// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PredictGame is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    //variables used for token and host

    ERC20 private ERC20interface;    
    address public tokenAdress; // This is the token address
    address payable public host; // This is the client
    uint256 public total_token = 0;
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);


    //variables used for oracle
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    
    event RequestVolume(bytes32 indexed requestId, uint256 volume);
    // mapping(uint256 => uint256) public ethUsdPrices; // Stores the ETH/USD price for each day

    //variables used for players
    struct Player{
        bool win;
        uint8 stage; // 스테이지는 0 ~ 6 까지 
        bool started;
        bool finished;
        uint256 betting_amount;
        uint256 startdate;
        uint temp; // temp 는 fulfill 함수에서 ethUsdPrices 를 차례대로 저장하기 위한 임시 증분값
        bool withdrawn;
    }
    mapping(address => uint256[7]) ethUsdPrices;
    mapping(address => Player) players;

    constructor() ConfirmedOwner(msg.sender){
        // change to your token address
        tokenAdress = 'your token address'; 
        ERC20interface = ERC20(tokenAdress);
        host = payable(msg.sender);
        //default values
        setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        setChainlinkOracle(0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD);
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)

    }
    // *********** Oracle functions *************//


    //  this function changes uint256 to string uint256ToString(uint256 ) => returns string
   /*  used in uint256ToString(timestamps[i]) .... 
        req.add(
                "get",
                string(abi.encodePacked("https://min-api.cryptocompare.com/data/pricehistorical?fsym=ETH&tsyms=USD&ts=", uint256ToString(timestamps[i])))
                
            );  */
    function uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // this function sends API calls to Chainlink data feed ex) https://min-api.cryptocompare.com/data/pricehistorical?fsym=ETH&tsyms=USD&ts=1689080582
    function get7DaysEthUsdPrices() public {
        uint256[] memory timestamps = get7DaysTimestamps(); // Helper function to get timestamps for the last 7 days
        
        for (uint256 i = 0; i < 7; i++) {

            Chainlink.Request memory req = buildChainlinkRequest(
                jobId,
                address(this),
                this.fulfill.selector
            );
            req.add(
                "get",
                string(abi.encodePacked("https://min-api.cryptocompare.com/data/pricehistorical?fsym=ETH&tsyms=USD&ts=", uint256ToString(timestamps[i])))
                
            );
            // Set the URL to perform the GET request on
    

            // Set the path to find the desired data in the API response
            req.add("path", "RAW,ETH,USD,VOLUME24HOUR");

            // Multiply the result by 1000000000000000000 to remove decimals
            int256 timesAmount = 10 ** 18;
            req.addInt("times", timesAmount);

            // Sends the request
            sendChainlinkRequest(req, fee);
        }
    }
    // Helper function to get timestamps for the last 7 days
    function get7DaysTimestamps() private view returns (uint256[] memory) {
        uint256[] memory timestamps = new uint256[](7);
        uint256 oneDay = 86400; // Number of seconds in a day

        for (uint256 i = 0; i < 7; i++) {
            timestamps[i] = block.timestamp - (i + 1) * oneDay;
            
        }

        return timestamps;
    }

    function fulfill(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        // Parse the requestId to get the day index (0-6) for the price
        emit RequestVolume(_requestId, _price);

        // mapping(address => uint256[7]) ethUsdPrices;
        ethUsdPrices[msg.sender][players[msg.sender].temp++] = _price; 
    }

    // *************** token functions ****************** //
    
    function contractBalance() public view returns (uint _amount){
        return ERC20interface.balanceOf(address(this));
    }
    
    function senderBalance() public view returns (uint){
        return ERC20interface.balanceOf(msg.sender);
    }
    
    function approveSpendToken(uint _amount) public returns(bool){
        return ERC20interface.approve(address(this), _amount); // We give permission to this contract to spend the sender tokens
        //emit Approval(msg.sender, address(this), _amount);
    }
    
    function allowance() public view returns (uint){
        return ERC20interface.allowance(msg.sender, address(this));
    }
    
    
    function depositTokens (uint256 _amount) internal {
        address from = msg.sender;
        address to = address(this);

        ERC20interface.transferFrom(from, to, _amount);
    }
    

    function transferBack (address payable _to, uint256 amount) private {
        uint balance = ERC20interface.balanceOf(address(this)); // the balance of this smart contract
        require(balance > amount,"The contract does not have enough tokens.");
        ERC20interface.transferFrom(address(this), _to, amount);
    }

    // ************ game functions *************** //
  /*   struct Player{
            bool win;
            uint8 stage;
            bool started;
            bool finished;
            uint256 betting_amount;
            uint256 startdate;
            uint256 temp;
            bool withdrawn;
        } */

    // 게임을 시작하는 함수,, Player 구조체를 초기화 하고 ethUsdPrices[] 배열에 ETH/USD 를 저장한다.
    function  startGame(uint256 _betting_amount) public{
        require(players[msg.sender].started != true, "the game has already started");
        depositTokens(_betting_amount);
        total_token += _betting_amount;
        players[msg.sender] = Player(false,0,true,false, _betting_amount,block.timestamp,0,false);
        get7DaysEthUsdPrices(); // 7개의 ETH/USD 가 fullfill 함수에 의해서 자동으로 ethUsdPrices[msg.sender] 에 저장된다.
    }
    // 게임을 진행 시키는 함수
    function  predict(bool up_down) public returns(bool){ // (true : up , false : down) 게임이 종료되면 true 를 반환한다.
        require(players[msg.sender].started == true , "game hasn't started yet");
        require(players[msg.sender].finished == false, "the game is already over");
        if(getStage() == 7){ // 마지막 스테이지 일 경우 게임을 종료 시킨다. 
            players[msg.sender].finished = true;
            players[msg.sender].win = true;
            return true;
        }
        // 틀렸을때 게임을 종료 시킨다.
        else if(ethUsdPrices[msg.sender][getStage()] > ethUsdPrices[msg.sender][getStage()+1] && up_down){ // up 이 틀렸을때
            players[msg.sender].finished = true; // 최종 저장된 stage 는 해당 유저가 아직 깨지 못한 stage 이다.
            players[msg.sender].win = false;
            return true;
        }
        else if(ethUsdPrices[msg.sender][getStage()] < ethUsdPrices[msg.sender][getStage()+1] && up_down){ // down 이 틀렸을때
            players[msg.sender].finished = true; // 최종 저장된 stage 가 해당 유저의 최대 stage 이다.
            players[msg.sender].win = false;
            return true;
        }
        else{ // 배팅에서 이겼을때
            players[msg.sender].stage++;
            return false;
        }
    }
    // 유저의 현제 스테이지를 리턴한다.
    function  getStage() public view returns(uint8){
        return players[msg.sender].stage;
    }

    // 게임을 종료 시키는 함수 전 스테이지에서 이겼을시 withdraw() 함수를 통해서 배팅 금액을 가져간다.
    function finishGame() public{
        require(players[msg.sender].finished == false, "the game is already over");
        require(players[msg.sender].started == true, "game hasn't started yet");
        players[msg.sender].finished = true;
        players[msg.sender].win = true;
    }


    // 게임이 끝났을시 인출 함수
    function withdraw() public {
        require(players[msg.sender].withdrawn == false, "You have already withdrawn.");
        require(players[msg.sender].finished == true, "the game is not over yet");
        require(players[msg.sender].win == true);
        transferBack(payable(msg.sender), players[msg.sender].betting_amount * players[msg.sender].stage);
    }
    
}