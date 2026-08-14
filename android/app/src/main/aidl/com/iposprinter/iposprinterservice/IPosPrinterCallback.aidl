package com.iposprinter.iposprinterservice;

interface IPosPrinterCallback {
    void onRunResult(boolean isSuccess);
    void onReturnString(String value);
}
