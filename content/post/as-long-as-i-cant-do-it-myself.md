+++
title = "As Long as I Can't Do It Myself"
date = 2018-04-14T15:07:43+02:00
description = "The client didn't want users to be able to download paid video content from their website."
draft = false
toc = false
categories = ["Frontend"]
tags = ["Javascript", "Video", "DRM", "AES", "Media Source Extensions", "MediaSource", "SourceBuffer"]
images = [
    "/img/aesvideo/screenshot.png"
] # overrides the site-wide open graph image
+++

**Disclaimer I: These post includes examples on BAD practices such as a bit of "roll your own crypto" and "security by obscurity". I DO NOT recommend to do this unless you understand all the downsides of this approach.**

**Disclaimer II: The approach followed here was chosen both as a _temporary_ solution to the problem which needed to be developed in a short time window (these took me about 6 hours to get it working).**

I'm developing a webpage for a client, which uses Firebase as backend. The owners upload videos to the server, which clients pay to watch. I was asked by the client to make these videos "as hard to download as possible". Of course when I was asked to do this, the first thing I thought about was DRM. But it turns that DRM solutions are quite complex to implement, require custom code running on backend. They're also quite expensive in terms of server CPU time. As this project started using Firebase (a choice I did not make), implementing custom and expensive backend logic wasn't the most desirable approach.

After discussing this with the client and telling them a proper solution would take long to land in production, they told me something in the lines of "as long as I can't do[wnload the videos] myself, it's ok to me" (translation by me, the original was, in spanish, "que no lo pueda hacer yo").

With this they meant someone without technical skills should not be able to download the video with some google-able process, like right-click -> download, or installing an addon. This made sense to me, as, in the end, anyone can just hit play and use a screen recording program to get the video ripped and then share it for free. So I start thinking about what could I do to prevent this.

Some requirements I set to myself were:

* Avoid using non-standard technologies

* Avoid using deprecated technologies (yes, I'm looking at you, Flash)

* Make it painless for the user

* Make it cross-platform (avoid silverlight & co.)

* Quick development time

Basically I could sum all of these in: "Do it using HTML5 and javascript only".

About the "don't let the users download the video (easily)", I mostly devised two things:

1. It should not appear as a media element in the page (aka, no `src=""`), so browsers and addons can't locate it.

2. The file downloaded must not be the video file "as-is", so in the case someone opens the dev tools panel, look at the network requests, and figure out the video url, can't just download it and play.

And so I decided to take the following approach: Upload the video file encrypted (preferrably symmetrically), and use some JS magick to decrypt it on the fly and feed it to the browser.

This, however, doesn't look like a trivial task, so let's dig into it.

<!--more-->

Searching about how to play a video from a custom byte stream was painful, as most documentaiton and posts you find are about newbie web devs who don't know their asses from their shoulders. The first possibility I thought about, which I later discarded but I find it fun enough to mention was [JSMPEG](http://jsmpeg.com/) ([github](https://github.com/phoboslab/jsmpeg)). This thing is both cool and terrible at the same time: Software-decoding video in Javascript. Amazing.

<center>![JSMPEG logo](/img/aesvideo/jsmpeg.png)</center>
<center>JSMPEG logo, but in white</center>

Apparently this could be an easy approach: This thing had to consume its data from some kind of byte stream, so it should be easy to download the ciphertext (well, ciphervideo), decrypt it, and then pass it to the decoder. However, it had its own drawbacks:

1. Software decoding in Javascript. I mean. ﻿Ｓｏｆｔｗａｒｅ  ｄｅｃｏｄｉｎｇ  ｉｎ  ｊａｖａｓｃｒｉｐｔ.

2. The exposed API was quite simple and only accepted sources from an URI (either http or websocket). That meant I would have to dig into the code, find the place were it actually downloaded the data, and put my own decryption logic in the middle. Painful.

3. It only worked with MPEG-1. Terrible. Say goodbye to HD options, apparently 720p30 was the maximum recommended resolution (which in fact is impressive for a software decoder in javascript)

4. S̸̡̛o̷̪̓f̴͚̌r̷͔͝w̴̼̆â̶͖r̶͓̚e̴̱̔ ̴̐͜d̴̫͆e̶͍̎c̸̲̒o̵̰̕d̵̰̅i̶̬͛ń̵̯g̵͇̈́ ̵̥̇i̸̹͒n̶̪̄ ̶͖͌j̷̠̄ḁ̶̔v̶͕̈́å̵̙s̴̽ͅč̵̱ṟ̷̚i̶̺͊p̴̺̋t̸̏ͅ

Fortunately for me, the client, and the users, I discarded this approach after discovering [Media Source Extensions](https://developer.mozilla.org/en-US/docs/Web/API/Media_Source_Extensions_API).

These APIs work roughly in the following way (for the thing I wanted to do):

```javascript
// Create a new MediaSource
// https://developer.mozilla.org/en-US/docs/Web/API/MediaSource

const ms = new MediaSource;

// Get the video MediaHTMLElement and assign it our MediaSource as src

const videoElement = document.getElementById(VIDEO_ID);

// https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement

videoElement.src = URL.createObjectURL(ms);

// When the MediaSource opens...
ms.addEventListener('sourceopen', () => {

    // Create a new SourceBuffer appended to the MediaSource
    // https://developer.mozilla.org/en-US/docs/Web/API/SourceBuffer
    const sourceBuffer = ms.addSourceBuffer(video.mime);

    // Create an array buffer
    // TODO: Do it from somewhere with actual data instead
    const emptyArray = new Uint8Array(1024);
    const buffer = emptyArray.buffer;

    // Append the video byte buffer to the sourceBuffer
    sourceBuffer.appendBuffer(buffer);
}
```

Note that the above code does not work at all, as it is incomplete and offered for demonstrative purposes only. Building a code that works by itself is left as an exercise for the reader. (Or you can contact me and hire me, of course).

Now, where can we get a buffer with some meaning? From a request, of course. So let's explore the [`fetch`](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API) API. I won't detail this a lot because it's far more common, but you can fetch the URL, get a [`Blob`](https://developer.mozilla.org/en/docs/Web/API/Blob) promise, and get an ArrayBuffer form the blob using [`FileReader`](https://developer.mozilla.org/en-US/docs/Web/API/FileReader). This roughly looks like:

```javascript
fetch(video.url).then((response) => {
    response.blob().then(function (blob) {
        const fr = new FileReader;

        // This event fires when the fileReader finishes reading the blob,
        //  and we have a buffer available on the `result` property.
        fr.addEventListener('load', () => {
            sourceBuffer.appendBuffer(fr.result);
        });

        fr.readAsArrayBuffer(blob);
    })
})
```

This should indeed work... Unless your video is big. And by big I mean around 5 Megabytes or more. If this is the case, the browser will throw a quota exceeding error and the video won't play at all.

How can we overcome this? Well, we have to modify our code so the buffers are added in chunks. By the way, I had to completely figure this out by myself, as it is not documented anywhere:

```javascript
fetch(video.url).then((response) => {
    response.blob().then(function (blob) {
        const fr = new FileReader;

        // We will use this to slice the buffer
        let offset = 0;

        // This event fires when the fileReader finishes reading the blob,
        //  and we have a buffer available on the `result` property.
        fr.addEventListener('load', () => {
            sourceBuffer.appendBuffer(fr.result);
            offset += VIDEO_CHUNK_SIZE;
        });

        // This event fires when the source buffer finishes appending the last buffer we enqueued using `appendBuffer()`.
        sourceBuffer.addEventListener('updateend', () => {

            if (offset <= blob.size) {
                // So, if we still have more blob remaining,
                // we ask the file reader to do process one part of the buffer. 
                
                fr.readAsArrayBuffer(blob.slice(offset, offset + VIDEO_CHUNK_SIZE))
            } else {
                // If not, we tell our MediaStream the video is finished.
                //  This just makes the video stop smoothly, instead of showing and endless load animation.

                console.log("Video downloaded successfully");
                ms.endOfStream();
            }
        });

        fr.readAsArrayBuffer(blob.slice(0, VIDEO_CHUNK_SIZE))
    })
})
```

The code above should work for any video size.

It's worth noting at this point the browser does not know where the video buffer is coming from, so it can't let the user download it (as far as I know). We're still downloading the video unencrypted though, so a clever user can still see the outgoing network request, and just open it in a new tab and save it. We need to store our video encrypted on the server, and then decrypt it on the browser, while we download it. So let's start with it.

For this part, any symmetric encryption algo would do the job, but I chose [`aesjs`](https://www.npmjs.com/package/aesjs), which is lightweight and (relatively) fast. I say relatively because it is pure JS, so welp.

Again, the code doing the decryption would look something along the lines of:

```javascript
fetch(video.url).then((response) => {
    response.blob().then(function (blob) {
        const fr = new FileReader;
        let decrypter = null;
        let offset = 0;

        sourceBuffer.addEventListener('updateend', () => {
            if (offset <= blob.size) {
                fr.readAsArrayBuffer(blob.slice(offset, offset + VIDEO_CHUNK_SIZE))
            } else {
                console.log("Video decrypted successfully");
                ms.endOfStream();
            }
        });

        fr.addEventListener('load', () => {
            const cipherBuf: ArrayBuffer = fr.result;
            let cipherData = new Uint8Array(cipherBuf);
            if (!decrypter) {
                decrypter = new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(cipherData.slice(0, 16)));
                // See explanation for this slice below.
                cipherData = cipherData.slice(16)
            }
            const buffer = decrypter.decrypt(cipherData).buffer;
            sourceBuffer.appendBuffer(buffer);
            offset += VIDEO_CHUNK_SIZE;
        });

        console.log("Starting video download and decryption");
        fr.readAsArrayBuffer(blob.slice(0, VIDEO_CHUNK_SIZE))
    })
})
```

You might have noticed (or maybe just read the comment telling you to read this) I do an initial .slice() of the response blob, and pass it to the AES CTR constructor. This is because AES needs an IV (a block of random bytes, send in clear along with the ciphertext) in order not to suck, which I prepend to the encrypted file when I process the video.

It is out of the scope of this post, but I also created a CLI tool in go which encrypts the video for me. You can find the source [on this gist](https://gist.github.com/roobre/b3d3553c74ea410bf340ad367d79fd27).

Yeah, yeah, I know what you're thinking: What about the key? Should it be the same for all videos? For all users? Should it be bundled statically on the frontend code? Retrieved from the backend perhaps? I'll leave that to your imagination. All of these choices are bad, and a competent researcher can figure out and get the videos decrypted. But all of that is, a) out of the scope of a two-day development, and b), way more complicated than recording the screen, which the client already assumes as a risk. Think about this as a cool way of complicating something which can't be made impossible.

<center>[![screenshot](/img/aesvideo/screenshot.jpg)](/img/aesvideo/screenshot.png)</center>
<center>Screenshot of the whole thing set up. Click for full-size image.</center>
