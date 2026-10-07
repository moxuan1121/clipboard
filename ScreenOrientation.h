// UIInterfaceOrientation values, not UIDeviceOrientation / sensor values.
static inline int CBScreenOrientation(int value) {
    return value >= 1 && value <= 4 && value != 2 ? value : 1;
}
