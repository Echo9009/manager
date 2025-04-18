#!/usr/bin/env python3

"""
AmneziaWG Configuration Encoder
Author: Improved by Claude
Version: 2.0

This script encodes AmneziaWG configuration files to a format
compatible with AmneziaVPN clients. It improves upon the original
with better error handling, security, and code organization.
"""

import json
import sys
import os
import logging
from typing import Dict, TypedDict, Optional, Any, Union
from pathlib import Path
try:
    from PyQt6.QtCore import QByteArray, qCompress
except ImportError:
    print("ERROR: PyQt6 is required. Install it with: pip3 install PyQt6")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename='/var/log/amnezia-encoder.log'
)
logger = logging.getLogger(__name__)

# Type definitions
class WireguardConfInterfaceData(TypedDict):
    """Interface parameters from wireguard .conf file"""
    PrivateKey: str
    Address: str
    DNS: str


class WireguardConfAdditionalInterfaceData(WireguardConfInterfaceData):
    """Additional parameters used by the amnezia-wg protocol"""
    Jc: Union[int, str]
    Jmin: Union[int, str]
    Jmax: Union[int, str]
    S1: Union[int, str]
    S2: Union[int, str]
    H1: Union[int, str]
    H2: Union[int, str]
    H3: Union[int, str]
    H4: Union[int, str]


class WireguardConfPeerData(TypedDict):
    """Peer parameters from wireguard .conf file"""
    PublicKey: str
    PresharedKey: str
    AllowedIPs: str
    Endpoint: str
    PersistentKeepalive: Optional[str]


class WireguardConfFullData(TypedDict):
    """Complete wireguard configuration data"""
    Interface: WireguardConfInterfaceData
    Peer: WireguardConfPeerData


# Constants for AmneziaWG protocol
AMNEZIA_PROTOCOL_PARAMS = {
    'Jc': '7',
    'Jmin': '50',
    'Jmax': '1000',
    'S1': '116',
    'S2': '61',
    'H1': '1139437039',
    'H2': '1088834137',
    'H3': '977318325',
    'H4': '1583407056'
}

DNS_SERVERS = {
    'primary': '1.1.1.1',
    'secondary': '1.0.0.1'
}


def pack(data_str: str) -> str:
    """
    Compress and encode the JSON configuration data
    
    Args:
        data_str: JSON string to compress and encode
        
    Returns:
        Base64 encoded and compressed string
        
    Raises:
        ValueError: If the input is not valid JSON
    """
    try:
        # Validate JSON
        json.loads(data_str)
    except json.JSONDecodeError as e:
        error_msg = f"Invalid JSON: {str(e)}"
        logger.error(error_msg)
        raise ValueError(error_msg)
    
    try:
        # Compress and encode using PyQt6
        byte_array = QByteArray(data_str.encode())
        compressed = qCompress(byte_array)
        encoded = compressed.toBase64(
            QByteArray.Base64Option.Base64UrlEncoding | 
            QByteArray.Base64Option.OmitTrailingEquals
        )
        return str(encoded, 'utf-8')
    except Exception as e:
        error_msg = f"Encoding failed: {str(e)}"
        logger.error(error_msg)
        raise RuntimeError(error_msg)


class WireguardConfParser:
    """Parser for Wireguard configuration files"""
    
    def __init__(self, conf_file: str):
        """
        Initialize the parser with a configuration file path
        
        Args:
            conf_file: Path to the configuration file
            
        Raises:
            FileNotFoundError: If the configuration file does not exist
        """
        self.conf_file = conf_file
        if not os.path.exists(conf_file):
            error_msg = f"Configuration file not found: {conf_file}"
            logger.error(error_msg)
            raise FileNotFoundError(error_msg)
    
    def read_data(self) -> str:
        """
        Read the configuration file content
        
        Returns:
            String containing the file content
            
        Raises:
            IOError: If there is an error reading the file
        """
        try:
            with open(self.conf_file, 'r') as file:
                return file.read()
        except IOError as e:
            error_msg = f"Error reading configuration file: {str(e)}"
            logger.error(error_msg)
            raise IOError(error_msg)
    
    def pack_config_data(self) -> WireguardConfFullData:
        """
        Parse the configuration file and return structured data
        
        Returns:
            Structured WireguardConfFullData with interface and peer information
            
        Raises:
            ValueError: If the configuration is invalid or missing required fields
        """
        wireguard_data: WireguardConfFullData = {
            'Interface': {},
            'Peer': {}
        }
        
        interface_data: Dict[str, Any] = {}
        peer_data: Dict[str, Any] = {}
        
        try:
            data = self.read_data()
            parsing_mode = ""
            
            for line in data.split('\n'):
                line = line.strip()
                
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                
                # Determine section
                if line == '[Interface]':
                    parsing_mode = 'interface'
                    continue
                elif line == '[Peer]':
                    parsing_mode = 'peer'
                    continue
                
                # Skip lines that don't contain key-value pairs
                if '=' not in line:
                    continue
                
                # Parse key-value pairs
                key, value = [l.strip() for l in line.split('=', 1)]
                
                if parsing_mode == 'interface':
                    interface_data[key] = value
                elif parsing_mode == 'peer':
                    peer_data[key] = value
            
            # Verify required fields
            required_interface_fields = ['PrivateKey', 'Address']
            required_peer_fields = ['PublicKey', 'Endpoint', 'AllowedIPs']
            
            for field in required_interface_fields:
                if field not in interface_data:
                    raise ValueError(f"Missing required interface field: {field}")
            
            for field in required_peer_fields:
                if field not in peer_data:
                    raise ValueError(f"Missing required peer field: {field}")
            
            wireguard_data['Interface'] = interface_data
            wireguard_data['Peer'] = peer_data
            
            return wireguard_data
        
        except Exception as e:
            error_msg = f"Error parsing configuration: {str(e)}"
            logger.error(error_msg)
            raise ValueError(error_msg)


def unpack_config_data(packed_config_data: WireguardConfFullData) -> str:
    """
    Convert structured configuration data back to string format
    
    Args:
        packed_config_data: Structured configuration data
        
    Returns:
        String representation of the configuration
    """
    data = ['[Interface]']
    
    # Process interface section
    for interface_key, value in packed_config_data['Interface'].items():
        # Handle special cases
        if interface_key == 'Address' and ',' in value:
            value = value.split(',')[0]
        if interface_key == 'DNS' and ',' in value:
            value = value.split(',')[0]
        
        data.append(f"{interface_key} = {value}")
    
    # Process peer section
    data.append('\n[Peer]')
    for peer_key, value in packed_config_data['Peer'].items():
        data.append(f"{peer_key} = {value}")
    
    return "\n".join(data)


def add_protocol_parameters(config_data: WireguardConfFullData) -> None:
    """
    Add AmneziaWG protocol parameters to the configuration
    
    Args:
        config_data: Configuration data to update (modified in-place)
    """
    config_data['Interface'].update(AMNEZIA_PROTOCOL_PARAMS)


class AmneziaWgBuilder:
    """Generator for AmneziaWG configuration data"""
    
    def __init__(self, wireguard_config_data: WireguardConfFullData, description: str):
        """
        Initialize the builder with configuration data and description
        
        Args:
            wireguard_config_data: Structured configuration data
            description: Description for the configuration
        """
        self.config_data = wireguard_config_data
        self.description = description
    
    def build(self) -> str:
        """
        Build and encode the configuration
        
        Returns:
            Encoded configuration string
        """
        json_data = self.generate_json()
        return pack(json_data)
    
    def get_formatted_config(self) -> str:
        """
        Get a formatted string representation of the configuration
        
        Returns:
            Formatted configuration string with protocol parameters
        """
        config_copy = self.config_data.copy()
        add_protocol_parameters(config_copy)
        return unpack_config_data(config_copy).replace('\n', '\\n')
    
    def get_client_ip(self) -> str:
        """
        Extract client IP address from configuration
        
        Returns:
            Client IP address
        """
        return self.config_data["Interface"]["Address"].split(",")[0].split('/')[0]
    
    def generate_json(self) -> str:
        """
        Generate JSON configuration for AmneziaVPN client
        
        Returns:
            JSON string containing the full configuration
        """
        try:
            # Extract configuration values
            client_ip = self.get_client_ip()
            client_priv_key = self.config_data['Interface']['PrivateKey']
            config_str = self.get_formatted_config()
            
            # Parse endpoint
            endpoint = self.config_data['Peer']['Endpoint']
            if ':' in endpoint:
                host_name, port = endpoint.split(':', 1)
            else:
                host_name = endpoint
                port = "39547"  # Default port
            
            psk_key = self.config_data['Peer'].get("PresharedKey", "")
            server_pub_key = self.config_data['Peer']['PublicKey']
            
            # Core configuration
            last_config = {
                "H1": AMNEZIA_PROTOCOL_PARAMS["H1"],
                "H2": AMNEZIA_PROTOCOL_PARAMS["H2"],
                "H3": AMNEZIA_PROTOCOL_PARAMS["H3"],
                "H4": AMNEZIA_PROTOCOL_PARAMS["H4"],
                "Jc": AMNEZIA_PROTOCOL_PARAMS["Jc"],
                "Jmax": AMNEZIA_PROTOCOL_PARAMS["Jmax"],
                "Jmin": AMNEZIA_PROTOCOL_PARAMS["Jmin"],
                "S1": AMNEZIA_PROTOCOL_PARAMS["S1"],
                "S2": AMNEZIA_PROTOCOL_PARAMS["S2"],
                "client_ip": client_ip,
                "client_priv_key": client_priv_key,
                "client_pub_key": "0",
                "config": config_str,
                "hostName": host_name,
                "port": port,
                "psk_key": psk_key,
                "server_pub_key": server_pub_key
            }
            
            # Complete JSON structure
            json_value = {
                "containers": [
                    {
                        "awg": {
                            "H1": AMNEZIA_PROTOCOL_PARAMS["H1"],
                            "H2": AMNEZIA_PROTOCOL_PARAMS["H2"],
                            "H3": AMNEZIA_PROTOCOL_PARAMS["H3"],
                            "H4": AMNEZIA_PROTOCOL_PARAMS["H4"],
                            "Jc": AMNEZIA_PROTOCOL_PARAMS["Jc"],
                            "Jmax": AMNEZIA_PROTOCOL_PARAMS["Jmax"],
                            "Jmin": AMNEZIA_PROTOCOL_PARAMS["Jmin"],
                            "S1": AMNEZIA_PROTOCOL_PARAMS["S1"],
                            "S2": AMNEZIA_PROTOCOL_PARAMS["S2"],
                            "last_config": json.dumps(last_config, indent=4),
                            "port": port,
                            "transport_proto": "udp"
                        },
                        "container": "amnezia-awg"
                    }
                ],
                "defaultContainer": "amnezia-awg",
                "description": self.description,
                "dns1": DNS_SERVERS["primary"],
                "dns2": DNS_SERVERS["secondary"],
                "hostName": host_name
            }
            
            return json.dumps(json_value, indent=4)
            
        except Exception as e:
            error_msg = f"Error generating JSON: {str(e)}"
            logger.error(error_msg)
            raise RuntimeError(error_msg)


def encode_config(user_id: str, config_path: str = None) -> str:
    """
    Encode configuration for a specific user
    
    Args:
        user_id: User identifier
        config_path: Path to configuration file (optional)
        
    Returns:
        Encoded configuration string
    """
    try:
        # Determine configuration path
        if not config_path:
            config_path = f'/etc/amnezia/amneziawg/keys/{user_id}/{user_id}.conf'
        
        # Validate file exists
        if not os.path.exists(config_path):
            error_msg = f"Configuration file not found: {config_path}"
            logger.error(error_msg)
            raise FileNotFoundError(error_msg)
        
        # Parse and encode configuration
        logger.info(f"Encoding configuration for user {user_id}")
        parser = WireguardConfParser(config_path)
        config_data = parser.pack_config_data()
        
        description = f'AmneziaVPN_{user_id}'
        builder = AmneziaWgBuilder(config_data, description)
        encoded = builder.build()
        
        logger.info(f"Successfully encoded configuration for user {user_id}")
        return encoded
        
    except Exception as e:
        error_msg = f"Failed to encode configuration: {str(e)}"
        logger.error(error_msg)
        print(f"ERROR: {error_msg}")
        sys.exit(1)


def main():
    """Main function for command-line execution"""
    # Verify arguments
    if len(sys.argv) != 2:
        print("Usage: python encode.py <user_id>")
        sys.exit(1)
    
    user_id = sys.argv[1]
    
    try:
        # Sanitize user_id to prevent path traversal
        if '/' in user_id or '..' in user_id:
            raise ValueError("Invalid user ID - contains path manipulation characters")
        
        # Encode and print configuration
        vpn_config = encode_config(user_id)
        print(vpn_config)
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
