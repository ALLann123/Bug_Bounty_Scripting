#!/usr/bin/python3
import os
import subprocess
import sys
import datetime

# Function to display tool banner/logo
def banner():
    print("""
    ██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║
    ██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║
    ██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║
    ██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝
    Bug Bounty Recon Automation - by @own_the_net
    """)  

# Function to create a unique output directory for each scan
def create_output_dir(domain):
    # Generate timestamp in format YYYYMMDD_HHMMSS
    timestamp=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

    # Create directory name using target domain + timestamp
    output_dir = f"recon_{domain}_{timestamp}"

    # Create the directory if it doesnt already exist
    os.makedirs(output_dir, exist_ok=True)

    # return the created directory path
    return output_dir


# function to run subfinder for subdomain enumeration
def run_subfinder(domain, output_dir):
    print(f"\n[*]Running Subfinder on {domain}.....")

    # Output file where discovered subdomains will be saved
    output_file = f"{output_dir}/subdomains.txt"

    # Build subfinder command
    cmd = f"subfinder -d {domain} -silent -o {output_file}"

    # Execute the command in the shell
    subprocess.run(cmd, shell=True)

    print(f"[+] SUbdomains saved to {output_file}")

    # Return output file path for later use
    return output_file

# Function to probe discovered subdomains for live hosts
def run_httpx(subdomains_file, output_dir):
    print("\n[*] Probing for live hosts with Httpx....")

    # File to save live hosts
    output_file=f"{output_dir}/live_hosts.txt"

    # HTTPX command:
    # -l   ---> input file containing subdomains
    # -silent   ---> reduce unnecessary output
    # -o -----> Save results to file
    # -status-code -----> show HTTP status codes
    # -title  ---> fetch webpage titles
    # -tech-detect   ----> detect technologies used
    cmd = (
        f"httpx -l {subdomains_file} "
        f"-silent -o {output_file} "
        f"-status-code -title -tech-detect"
    )

    # Execute command
    subprocess.run(cmd, shell=True)

    print(f"[+] Live hosts saved to {output_file}")

    # return live hosts file path
    return output_file

# Function to run Nuclei vulnerability scanning
def run_nuclei(live_hosts_file, output_dir):
    print("\n[*] Running Nuclei vulnerability scan.....")

    # output file for Nuclei results
    output_file = f"{output_dir}/nuclei_results.txt"

    # Nuclei command:
    # -l ----> input file containing live hosts
    # -severinity ---> only scan for selected severities
    # -o -----> save output
    # -silent  -----> cleaner output
    cmd = (
        f"nuclei -l {live_hosts_file} "
        f"-severity critical,high,medium "
        f"-o {output_file} -silent"
    )

    # Execute command
    subprocess.run(cmd, shell=True)

    print(f"[+] Nuclei results saved to {output_file}")

    # return nuclei results file
    return output_file

# Function to run NMAP for port scanning
def run_nmap(domain, output_dir):
    print(f"\n[*] Running NMAP port scan on {domain}.....")

    # output file for NMAP results
    output_file = f"{output_dir}/nmap_results.txt"

    # Nmap command:
    # -sV -----> service/version detection
    # --top-ports 1000 ----> scan top 1000 common ports
    # -oN   -----> save output in normal format
    cmd = f"nmap -sV --top-ports 1000 {domain} -oN {output_file}"

    # Execute Nmap Scan
    subprocess.run(cmd, shell=True)

    print(f"[+] Nmap results saved to {output_file}")


# Function to combine all results into one report
def generate_report(domain, output_dir):
    print("[*] Generate Final report....")
    
    # Final report filename
    report_file=f"{output_dir}/REPORT_{domain}.txt"

    # open report file in write mode
    with open(report_file, "w") as report:
        # Write report header
        report.write(f"====BUG BOUNTY RECON REPORT====\n")
        report.write(f"Target: {domain}\n")
        report.write(f"Date: {datetime.datetime.now()}\n")
        report.write(f"Tool: @own_the_net Recon Automation\n\n")

        # Loop through all files inside the output directory
        for filename in os.listdir(output_dir):

            # build full file path
            filepath = os.path.join(output_dir, filename)

            # only include .txt files except the report itself
            if filename.endswith(".txt") and filename != f"REPORT_{domain}.txt":

                # Add section separator
                report.write(f"\n{'='*50}\n")
                report.write(f"[{filename}]\n")
                report.write(f"{'='* 50}\n")

                # Read file contents and append to report
                with open(filepath, "r") as f:
                    report.write(f.read())

    print(f"\n[+] Report generated: {report_file}")
    print(f"[+] All files saved in: {output_dir}\n")


# Main program execution function
def main():
    # Display banner
    banner()

    # Check if user supplied exactly one argument
    if len(sys.argv) != 2:
        # show usage instructions
        print("[-] Usage: python3 recon.py <target-domain>")
        print("Example: python3 recon.py example.com")

        # Exit program with error status
        sys.exit(1)


    # Get target domain from command-line argument
    domain = sys.argv[1]

    # Create output directory
    output_dir=create_output_dir(domain)

    print(f"[+] Target: {domain}")
    print(f"[+] Output directory: {output_dir}")

    # step 1:  Enumerate subdomains
    subdomains_file= run_subfinder(domain, output_dir)

    # step 2: Probe live hosts
    live_hosts_file=run_httpx(subdomains_file, output_dir)

    # step 3: Scan live hosts with Nuclei
    run_nuclei(live_hosts_file, output_dir)

    # step 4: Run nmap scan
    run_nmap(domain, output_dir)

    # step 5: Generate combined report
    generate_report(domain, output_dir)


# Run the program only if executed directly
if __name__ == "__main__":
    main()

"""
root@delux:~/dark_kernel/automation# python3 main.py jkuat.ac.ke

    ██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║
    ██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║
    ██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║
    ██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝
    Bug Bounty Recon Automation - by @own_the_net
    
[+] Target: jkuat.ac.ke
[+] Output directory: recon_jkuat.ac.ke_20260512_200931

[*]Running Subfinder on jkuat.ac.ke.....
evaluation.jkuat.ac.ke
gems-techtest.jkuat.ac.ke
hostel.jkuat.ac.ke
jkuebms.jkuat.ac.ke
oldportal.jkuat.ac.ke
sodel2.jkuat.ac.ke
jipas.jkuat.ac.ke
kenviprepository.jkuat.ac.ke
monitoring.jkuat.ac.ke
ses.jkuat.ac.ke
kenvip-home.jkuat.ac.ke
dassa-smartlearning.jkuat.ac.ke
dharc-academy.jkuat.ac.ke

[+] SUbdomains saved to recon_jkuat.ac.ke_20260512_200931/subdomains.txt

[*] Probing for live hosts with Httpx....
https://drone.jkuat.ac.ke [200] [Drone Research Group at JKUAT] [Fastly,GitHub Pages,Varnish]                                                     
https://jkudhub.jkuat.ac.ke [200] [HSTS,Nginx:1.27.2]
https://application.jkuat.ac.ke [200] [JKUAT E-Services Admission Portal] [HSTS,Nginx:1.27.4]
http://jipas.jkuat.ac.ke [503] [503 Service Temporarily Unavailable] [Nginx]                                                                      
http://jipas3.jkuat.ac.ke [503] [503 Service Temporarily Unavailable] [Nginx]                                                                     
https://emailgen.jkuat.ac.ke [200] [Email Generator] [Bootstrap:4.5.3,Nginx:1.10.3,Ubuntu]                                                        
http://jipas2.jkuat.ac.ke [503] [503 Service Temporarily Unavailable] [Nginx]                                                                     
https://admission2024.jkuat.ac.ke [200] [JKUAT E-Services Admission Portal] [HSTS,Nginx:1.27.4]                                                   
https://bursary-jkusa.jkuat.ac.ke [502] [502 Bad Gateway] [Nginx:1.14.0,Ubuntu]                                                                   
https://admission.jkuat.ac.ke [200] [JKUAT E-Services Admission Portal] [HSTS,Nginx:1.27.4]                                                       
https://election.jkuat.ac.ke [302] [Redirecting to https://election.jkuat.ac.ke/login] [Laravel,Nginx:1.14.0,PHP,Ubuntu]  

"""