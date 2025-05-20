FROM python:3.9-slim
WORKDIR /app
COPY weave_app.py .
RUN pip install flask numpy pandas plotlty
CMD ["flask", "run", "--host=0.0.0.0"]

