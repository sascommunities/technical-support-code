FROM python:3.11
WORKDIR /app
COPY . .
RUN chmod +x gen-ai-monitor.sh
CMD ["sh", "-c", "./gen-ai-monitor.sh start && tail -f /dev/null"]
EXPOSE 8899