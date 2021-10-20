#!/usr/local/anaconda3/envs/alfred/bin/python3
# -*- coding: utf-8 -*-
import sys
import uuid
import requests
import base64
import hashlib
import os
import time
import json

YOUDAO_URL = "https://openapi.youdao.com/ocrapi"


def dump_clipboard_image():
    filename = "./tmp.jpg"
    ret = os.system("./pngpaste/pngpaste {}".format(filename))
    if ret != 0:
        raise ValueError("No image found in your clipboard.")
    with open(filename, "rb") as f:
        content = base64.b64encode(f.read()).decode("utf-8")
    os.system("rm {}".format(filename))
    if len(content) > 4 * 1024 * 1024:
        raise ValueError("Image should be smaller than 4M")
    return content


def truncate(q):
    if q is None:
        return None
    size = len(q)
    return q if size <= 20 else q[0:10] + str(size) + q[size - 10 : size]


def encrypt(signStr):
    hash_algorithm = hashlib.sha256()
    hash_algorithm.update(signStr.encode("utf-8"))
    return hash_algorithm.hexdigest()


def do_request(data):
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    return requests.post(YOUDAO_URL, data=data, headers=headers)


def connect():
    q = dump_clipboard_image()
    data = {}
    data["detectType"] = "10012"
    data["imageType"] = "1"
    data["langType"] = "auto"
    data["img"] = q
    data["docType"] = "json"
    data["signType"] = "v3"
    curtime = str(int(time.time()))
    data["curtime"] = curtime
    salt = str(uuid.uuid1())
    signStr = APP_KEY + truncate(q) + salt + curtime + APP_SECRET
    sign = encrypt(signStr)
    data["appKey"] = APP_KEY
    data["salt"] = salt
    data["sign"] = sign

    response = do_request(data)
    return response.json()


def main():
    try:
        ret = ""
        rawdata = connect()
        if rawdata["errorCode"] != "0":
            raise ValueError(
                "Connet to Youdao error with code{}!".format(rawdata["errorCode"])
            )
        result = rawdata["Result"]
        regions = result["regions"]
        for region in regions:
            lines = region["lines"]
            for line in lines:
                ret += line["text"] + "\n"
    except ValueError as e:
        title = "OCR Clipboard Error"
        content = e
    title = "Text Copied"
    content = ret
    dic = {
        "alfredworkflow": {
            "arg": "something",
            "config": {},
            "variables": {"title": title, "content": content},
        }
    }
    final = json.dumps(dic, ensure_ascii=False)
    print(final)


if __name__ == "__main__":
    APP_KEY = os.getenv("bce_api_key")
    APP_SECRET = os.getenv("bce_api_secret")
    main()

