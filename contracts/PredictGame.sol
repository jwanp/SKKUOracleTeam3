// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
contract Game is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    
    event RequestVolume(bytes32 indexed requestId, uint256 volume);
    mapping(uint256 => uint256) public ethUsdPrices; // Stores the ETH/USD price for each day

    constructor() ConfirmedOwner(msg.sender){
        setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        setChainlinkOracle(0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD);
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
    }
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
        uint256 dayIndex = uint256(_requestId);

        ethUsdPrices[dayIndex] = _price;
    }

    
}
