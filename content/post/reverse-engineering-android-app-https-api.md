+++
date = "2017-04-04T17:36:23+02:00"
title = "Reverse-engineering an Android app to get access to its HTTPS API"
description = "A commercial, privative Android app is suspected to use an HTTPS API to get the data it shows up. The ability to obtain this data is valuable to us, so we apply different reversing techniques to find out where this API is located and how to use it."
tags = ["RI","Android","REST","HTTPS"]
categories = ["Reversing"]
images = ["https://www.carrierlost.net/img/restapi/tmpblVJQk.png"]
draft = false
+++

*Disclaimer: For privacy (and maybe legal) reasons, we will not disclose identifying details of the app which was reverse engineered.*

As mentioned on the description, this post describes a (successful) attempt to discover the source of the data an Android app uses, which would allow us to write scripts and harvest this data for our own benefits.

The first reasonable assumption we make is that this source of data is an HTTP(s) API, probably REST. To test this out, we create an AVD (Android Virtual Device), throw the APK into it, and see what kind of traffic produces:

    $ /opt/android-sdk/tools/emulator -avd MarshmallowPutillax64
    $ /opt/android-sdk/platform-tools/adb install /tmp/target.apk

We launch wireshark along wiht our target app and wait:

<center>![wireshark](/img/restapi/tmpSXTrXY.png)</center>

As expected, most traffic is set via port 443, and a previous non-encrypted HTTP requests seems to hint that this later traffic is indeed HTTPS. It's time to start playing with proxies.

Fortunately, the android emulator has native support for HTTP Proxies. This is, we can tell the emulator to transparently forward any HTTP(s) requests through a user-defined proxy. To accomplish this, we just launch the emulator with the proper CLI option:

    $ /opt/android-sdk/tools/emulator -avd MarshmallowPutillax64 -http-proxy 127.0.0.1:8080

Of course, we have some kind of MITM-capable proxy on port 8080 of our machine. There are several options out there, like `mitmproxy` or Burp Suite. I'll use the later, simply because I'm more used to it.

Of course this isn't enough. The proxy will intercept HTTPs connections on the fly and generate a custom ca-signed certificate for each domain, but the system won't trust these certificates. To bypass this restriction, we need to export the CA certificate the proxy uses, and add it to the Android system..

<center>![burpca](/img/restapi/tmpiSTrGQ.png)</center>

We can now adb push this file to the AVD and add it via the system settings:

    $ /opt/android-sdk/platform-tools/adb push /tmp/ca.crt /sdcard

After adding it to the system, we can now try to access any site with the web browser, and the certificates will be seen as good. And of course, the traffic log will appear in our proxy software.

<center>![androidbrowser](/img/restapi/tmpblVJQk.png)</center>

Now it's time to try with the app!

<!--more-->

... with little success. Our target app just stucks on the loading screen. Nani the fuck? Well, if we look at the proxy log, we can see an awful and well-known warning:

<center>![certerror](/img/restapi/tmpfRAFx5.png)</center>

What is happening here? Well, this is maybe the most interesting part of this post. It turns that Java (and of course Android) SSL APIs allow the programmers to add a list of CA certificates they trust, and discard any others, even if the systems sees them as valid. The details of these APIs is out of the scope of this post, but the key part here is that this "list" usually has the `.bks` file extension, and of course it's encrypted.

So we just list the file contents of our apk and check for `.bks` files:

    $ unzip -l target.apk | grep bks
     5▒▒▒▒  2017-▒▒-▒▒ ▒▒:37   res/raw/keystore▒▒▒▒▒production▒.bks

(Some info has been manually censored to strip identifying information)

Voilà. We can now extract this file and start playing with it.

BKS files, as said a few paragrapghs above, are Bouncy Castle truststores (ca certificate lists). There are a few tools we can use to mess with this files, being Java CLI `keytool` and GUI Portecle the most used. BKS files are kind of complicated and some third-party libraries are needed to work with them. You can easily look for this info on your favourite search engine. For now, you can trust me and hope this command actually lists the valid CAs inside the truststore:

    keytool -list -keystore /tmp/keystore▒▒▒▒▒production▒.bks -storetype BKS -provider org.bouncycastle.jce.provider.BouncyCastleProvider -providerpath /tmp/bcprov-ext-jdk15on-1.46.jar

Of course, as this file is encrypted, we need a password to read and/or modify it. My first attempt was to write a simple shell script which reads passwords from `stdin` (in practice, an `xzcat`d dictionary) and tries to open the file with the given password:

    $ cat bruteforce.sh 
    #!/bin/sh

    result=0

    while read password; do
        [[ $result -ne 0 ]] || echo $password | keytool -list -keystore /tmp/keystore▒▒▒▒▒production▒.bks -storetype BKS -provider org.bouncycastle.jce.provider.BouncyCastleProvider -providerpath /tmp/bcprov-ext-jdk15on-1.46.jar
        result=$?
    done

Nothing fancy, just a shitty (and VERY slow) dictionary attack.

Of course it didn't work. The chances that the password was on the dictionary were slim, and invoking a JVM instance per try is slow af. Also, this password is used directly from the app code, so it doesn't need to be human-readable at all.

... wait. Did I just said it's used from the app code? Then let's just decompile it and search for it!

If we talk about decompiling APKs, `apktool` comes into play. It's pretty simple to use, and it's perfectly described on their [documentation](https://ibotpeaches.github.io/Apktool/).

Let's throw our APK to apktool and see what happens.

    $ apktool d target.apk 
    I: Using Apktool 2.2.1 on target.apk
    I: Loading resource table...
    I: Decoding AndroidManifest.xml with resources...
    I: Loading resource table from file: /home/roobre/.local/share/apktool/framework/1.apk
    I: Regular manifest package...
    I: Decoding file-resources...
    I: Decoding values */* XMLs...
    I: Baksmaling classes.dex...
    I: Copying assets and libs...
    I: Copying unknown files...
    I: Copying original files...


    $ l target
    total 8.0K
    drwxr-xr-x   6 roobre roobre  160 Apr  5 15:21 .
    drwxrwxrwt  20 root   root   1.2K Apr  5 15:21 ..
    -rw-r--r--   1 roobre roobre 1.5K Apr  5 15:21 AndroidManifest.xml
    -rw-r--r--   1 roobre roobre  391 Apr  5 15:21 apktool.yml
    drwxr-xr-x   2 roobre roobre   60 Apr  5 15:21 assets
    drwxr-xr-x   2 roobre roobre   60 Apr  5 15:21 original
    drwxr-xr-x 125 roobre roobre 2.5K Apr  5 15:21 res
    drwxr-xr-x   6 roobre roobre  120 Apr  5 15:21 smali

We can see the res folder with the resources we saw earlier. Of course the BKS file we extracted with unzip is also there. Let's ignore it for now, as we already have it. The interesting stuff is inside the `smali` folder:

    $ find target/smali -maxdepth 2
    target/smali
    target/smali/org
    target/smali/org/xmlpull
    target/smali/org/simpleframework
    target/smali/org/c
    target/smali/org/b
    target/smali/org/a
    target/smali/de
    target/smali/de/greenrobot
    target/smali/com
    target/smali/com/▒▒▒▒▒
    target/smali/com/astuetz
    target/smali/com/adobe
    target/smali/com/a
    target/smali/android
    target/smali/android/support

What we are seeing is the java package structure replicated and decompiled there. Of course, there's a lot of files and a lot of code. We need to find somehow which classes are related to our BKS file, and then inspect them in detail. As this classes work with keystores, the `keystore` word may appear somewhere near it, right? Let's `grep` it accross all the source files.

    $ grep -Rie keystore target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒ 
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/n.smali:.field public static final keystore▒▒▒▒▒production4:I = 0x7f060000
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/f.smali:.field private final synthetic b:Ljava/security/KeyStore;
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/f.smali:.method constructor <init>(Lcom/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e;Ljava/security/KeyStore;)V
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/f.smali:    iput-object p2, p0, Lcom/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/f;->b:Ljava/security/KeyStore;
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/f.smali:    iget-object v1, p0, Lcom/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/f;->b:Ljava/security/KeyStore;
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/f.smali:    invoke-virtual {v0, v1}, Ljavax/net/ssl/TrustManagerFactory;->init(Ljava/security/KeyStore;)V
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e.smali:.method private a(Landroid/content/Context;)Ljava/security/KeyStore;
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e.smali:    invoke-static {v0}, Ljava/security/KeyStore;->getInstance(Ljava/lang/String;)Ljava/security/KeyStore;
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e.smali:    invoke-virtual {v0, v1, v2}, Ljava/security/KeyStore;->load(Ljava/io/InputStream;[C)V
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e.smali:.method private a(Ljava/security/KeyStore;)Ljavax/net/ssl/SSLSocketFactory;
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e.smali:    invoke-virtual {v0, p1}, Ljavax/net/ssl/TrustManagerFactory;->init(Ljava/security/KeyStore;)V
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e.smali:    invoke-direct {v1, p0, p1}, Lcom/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/f;-><init>(Lcom/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e;Ljava/security/KeyStore;)V
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e.smali:    invoke-direct {p0, v1}, Lcom/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e;->a(Landroid/content/Context;)Ljava/security/KeyStore;
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e.smali:    invoke-direct {p0, v1}, Lcom/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e;->a(Ljava/security/KeyStore;)Ljavax/net/ssl/SSLSocketFactory;
    target/smali/com/▒▒▒▒▒/▒▒▒▒▒▒▒▒▒▒▒▒▒/f/e.smali:    .catch Ljava/security/KeyStoreException; {:try_start_0 .. :try_end_0} :catch_1

Nice! We reduced our search to just two files, which also live inside the same package. That's promising. Let's look at these files in detail:

<center>![password](/img/restapi/tmpkuFwKz.png)</center>

Tee-hee. That looks like a password to me.

    $ keytool -list -keystore /tmp/keystore▒▒▒▒▒production▒.bks -storetype BKS -provider org.bouncycastle.jce.provider.BouncyCastleProvider -providerpath /tmp/bcprov-ext-jdk15on-1.46.jar
    Enter keystore password:  

    Keystore type: BKS
    Keystore provider: BC

    Your keystore contains 4 entries

    root, Nov 9, 2014, trustedCertEntry, 
    Certificate fingerprint (SHA1): ▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒
    ▒▒, Nov 9, 2014, trustedCertEntry, 
    Certificate fingerprint (SHA1): ▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒
    ▒▒▒.▒▒▒▒▒.es, Nov 9, 2014, trustedCertEntry, 
    Certificate fingerprint (SHA1): ▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒
    ▒▒▒, Nov 9, 2014, trustedCertEntry, 
    Certificate fingerprint (SHA1): ▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒:▒▒

evillaugh.wav

Now let's load the file on a faster GUI tool like Portecle, delete all current certificates and replace them with our `ca.crt` exported from Burp Suite.

We save the file, replacing the old one, and we recompile all with apktool:

    $ apktool b
    I: Using Apktool 2.2.1
    I: Checking whether sources has changed...
    I: Smaling smali folder into classes.dex...
    I: Checking whether resources has changed...
    I: Building resources...
    I: Building apk file...
    I: Copying unknown files/dir...

Now we need to pass through the usual jar signing proccess. We create a keystore with

    $ keytool -genkey -keystore whocares.keystore -validity 10000 -alias whocares

And sign the APK with 

    $ jarsigner -keystore whocares.keystore -verbose target.apk whocares

Then, we uninstall the legit APK from the emulator and push the modified one.

<center>![proxy](/img/restapi/tmpDCdGH6.png)</center>

(I'm to lazy to properly mask all of these. And honestly, if you can bruteforce the blur, you also can break this app. So I dont give a shit about it.)

Now, this is it!

We can now just play with the app, make some request, replay them, etc. Pretty nice, isn't it?
