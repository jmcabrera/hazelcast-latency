import com.hazelcast.client.ClientConfig;
import com.hazelcast.client.HazelcastClient;
import com.hazelcast.core.HazelcastInstance;
import com.hazelcast.core.IMap;
import lombok.val;

import java.util.Date;

import static java.lang.System.err;
import static java.lang.System.setProperty;

public class Client25 {

  public static void main(String[] args) {

    // https://docs.hazelcast.org/docs/2.5/manual/html-single/index.html#ConfigurationProperties
    setProperty("hazelcast.logging.type", "slf4j");
//    setProperty("hazelcast.redo.log.threshold", "3");
//    setProperty("hazelcast.redo.giveup.threshold", "10");
//    setProperty("hazelcast.max.operation.timeout", "500");
    setProperty("hazelcast.client.invocation.timeout.seconds", "3");

    val clientConfig = new ClientConfig().addAddress("127.2.1.1:5701", "127.2.1.2:5701");

    HazelcastInstance client = HazelcastClient.newHazelcastClient(clientConfig);
    ((HazelcastClient) client).getClientConfig().setConnectionTimeout(2);
    IMap map = client.getMap("customers");
    while (true) {
      try {
        Thread.sleep(1000);
        map.put("" + new Object(), "" + new Object());
        err.println(new Date() + ": Map Size:" + map.size());
      } catch (Throwable t) {
        t.printStackTrace();
//        err.println("reassigning client");
//        client = HazelcastClient.newHazelcastClient(clientConfig);
//        map = client.getMap("customers");
      }
    }


}
}
