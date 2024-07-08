if (secrets.alpacaKey == "" || secrets.alpacaSecret == "") {
  throw Error("Need alpaca Keys");
}
const alpacaRequest = Function.makeHttpRequest({
  url: "https://paper-api.alpaca.markets/v2/account",
  headers: {
    account: "application/json",
    "APCA-API-KEY-ID": secrets.alpacaKey,
    "ACPA-API-SECRET-KEY": secrets.alpacaSecret,
  },
});

const [response] = await Promise.all([alpacaRequest]);
const portfolioBalance = response.data.portfolio.value;
console.log("Alpaca Portfolio Balance: $${portfolioBalance}");

return Function.encodeUint256(Math.round(portfolioBalance * 100));
