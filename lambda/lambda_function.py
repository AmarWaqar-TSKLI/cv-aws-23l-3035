import base64
import json
import os
import time

import boto3

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]
PREFIX = os.environ["PREFIX"]

ROUTES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/cv.pdf": ("cv.pdf", "application/pdf"),
}

NOT_FOUND_PAGE = (
    "<!DOCTYPE html><html><head><title>404 Not Found</title></head>"
    "<body><h1>404 - Not Found</h1><p>That page does not exist. "
    '<a href="/">Back to the CV</a></p></body></html>'
)


def lambda_handler(event, context):
    start = time.time()
    path = event.get("rawPath", "/")

    if path not in ROUTES:
        response = {
            "statusCode": 404,
            "headers": {"Content-Type": "text/html; charset=utf-8"},
            "body": NOT_FOUND_PAGE,
        }
    else:
        name, content_type = ROUTES[path]
        try:
            body = s3.get_object(Bucket=BUCKET, Key=PREFIX + name)["Body"].read()
            if name == "index.html":
                html = body.decode("utf-8").replace(
                    "{{HOSTED_ON}}", "Lambda " + context.function_name
                )
                response = {
                    "statusCode": 200,
                    "headers": {"Content-Type": content_type, "Cache-Control": "max-age=60"},
                    "body": html,
                }
            elif name == "cv.pdf":
                response = {
                    "statusCode": 200,
                    "headers": {"Content-Type": content_type},
                    "body": base64.b64encode(body).decode("ascii"),
                    "isBase64Encoded": True,
                }
            else:
                response = {
                    "statusCode": 200,
                    "headers": {"Content-Type": content_type},
                    "body": body.decode("utf-8"),
                }
        except Exception as err:
            print(json.dumps({"error": str(err)}))
            response = {
                "statusCode": 500,
                "headers": {"Content-Type": "text/plain"},
                "body": "Internal error",
            }

    print(json.dumps({
        "fn": context.function_name,
        "path": path,
        "status": response["statusCode"],
        "ms": round((time.time() - start) * 1000, 1),
    }))
    return response
