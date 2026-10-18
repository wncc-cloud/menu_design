/// Test / non-web recorder so behaviour can be asserted without a browser.
String? lastTabTitle;
int vibrations = 0;

void setTabTitle(String? title) => lastTabTitle = title;

void vibrateOnce() => vibrations++;
